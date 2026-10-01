// Brick/BAS live-data bridge: a small local process between the game and a Niagara station
// running the baskStream service. The game (Godot) speaks JSON text frames over
// ws://127.0.0.1:<port>/baskstream; the bridge holds the station session with the
// @basidekick/baskstream SDK (Niagara SCRAM login, keepalive, reconnects, leased live
// subscriptions) and translates.
//
// Read-only by design: only the operations listed in OPS exist here, and none of them
// writes, acknowledges, schedules or edits anything on a station.
//
// Game -> bridge   {op, id, ...}
//   hello       {token}                                  first frame when a token is set
//   connect     {station, username, password, allowSelfSigned, name}
//   disconnect  {}
//   browse      {ord}                    -> {node, children}
//   search      {query, limit}           -> {nodes, truncated}
//   describe    {ord}                    -> {node}
//   read        {points}                 -> {points}
//   watch       {points}                 -> {points}       then pushes {op: "values", points}
//   history     {ord, hours}             -> {buckets}
//   alarms      {}                       -> {alarms}
// Bridge -> game   {op: "<op>_result", id, ...} | {op: "error", id, code, message}
//                  {op: "status", status, message, info} | {op: "values", points}

import { realpathSync } from 'node:fs'
import http from 'node:http'
import { fileURLToPath } from 'node:url'
import { BaskStreamClient, BaskStreamError, toSlotOrd } from '@basidekick/baskstream'
import { WebSocket, WebSocketServer } from 'ws'

const HOST = '127.0.0.1'
const PORT = Number(argValue('--port') || process.env.BRICK_BAS_BRIDGE_PORT || 8789)
const TOKEN = argValue('--token') || process.env.BRICK_BAS_BRIDGE_TOKEN || ''
const MAX_LIVE_POINTS = 500
const VALUE_FLUSH_MS = 120
const OPS = new Set(['hello', 'connect', 'disconnect', 'browse', 'search', 'describe', 'read', 'watch', 'history', 'alarms', 'ping'])

function argValue(name) {
	const hit = process.argv.find((arg) => arg.startsWith(name + '='))
	return hit ? hit.slice(name.length + 1) : ''
}

const str = (value) => (typeof value === 'string' && value ? value : null)

export function toNode(node) {
	return {
		ord: toSlotOrd(node.ord),
		name: node.name,
		display: str(node.display) ?? node.name,
		kind: str(node.kind) ?? 'component',
		typeSpec: str(node.typeSpec) ?? '',
		hasChildren: Boolean(node.hasChildren),
		writable: Boolean(node.writable),
		status: str(node.status),
	}
}

export function toValue(snapshot) {
	const facets = snapshot.facets ?? {}
	return {
		point: toSlotOrd(snapshot.point),
		ok: Boolean(snapshot.ok),
		value: snapshot.value ?? null,
		display: str(snapshot.displayValue) ?? (snapshot.value === undefined ? '—' : String(snapshot.value)),
		status: str(snapshot.status) ?? (snapshot.ok ? '{ok}' : '{unknown}'),
		timestamp: typeof snapshot.timestamp === 'number' ? snapshot.timestamp : null,
		valueType: str(snapshot.valueType),
		units: str(facets.units),
	}
}

export function stationOrigin(raw) {
	const text = String(raw ?? '').trim()
	if (!text) throw new BaskStreamError('bad_request', 'Enter the station address.')
	let url
	try {
		url = new URL(text.includes('://') ? text : `https://${text}`)
	} catch {
		throw new BaskStreamError('bad_request', "That station address isn't a valid URL.")
	}
	if (url.protocol === 'wss:') url.protocol = 'https:'
	if (url.protocol === 'ws:') url.protocol = 'http:'
	if (url.protocol !== 'https:' && url.protocol !== 'http:') throw new BaskStreamError('bad_request', 'Use an http(s):// station address.')
	if (url.username || url.password) throw new BaskStreamError('bad_request', "Don't put credentials in the address.")
	return url.origin
}

export function friendly(error) {
	if (error instanceof BaskStreamError) {
		switch (error.code) {
			case 'login_failed': return 'The station refused the login. Check the username and password.'
			case 'session_expired': return 'The station session expired. Connect again.'
			case 'timeout': return "The station didn't answer in time."
			case 'not_connected': case 'connection_closed': return 'Not connected to the station.'
			case 'auth_required': return 'The station needs a login.'
			default: return error.message || error.code
		}
	}
	const message = error instanceof Error ? error.message : String(error)
	if (/self[- ]signed|certificate/i.test(message)) return "The station's certificate isn't trusted. Tick \"Allow self-signed\" if you trust this station."
	if (/ECONNREFUSED|ENOTFOUND|EHOSTUNREACH|ETIMEDOUT/.test(message)) return `Can't reach the station (${message.split(' ')[0]}).`
	return message
}

// One game connection: its station client, live watch and pending value pushes.
class Session {
	constructor(socket) {
		this.socket = socket
		this.authenticated = !TOKEN
		this.client = null
		this.watch = null
		this.info = null
		this.pending = new Map()
		this.flushTimer = null
		this.watchUpdate = Promise.resolve()
		this.generation = 0 // bumped by close(), so a login that finishes late is dropped
	}

	send(message) {
		if (this.socket.readyState === WebSocket.OPEN) this.socket.send(JSON.stringify(message))
	}

	status(status, message = null) {
		this.send({ op: 'status', status, message, info: this.info })
	}

	queueValue(snapshot) {
		const value = toValue(snapshot)
		this.pending.set(value.point, value)
		if (!this.flushTimer) this.flushTimer = setTimeout(() => this.flush(), VALUE_FLUSH_MS)
	}

	flush() {
		this.flushTimer = null
		if (this.pending.size === 0) return
		this.send({ op: 'values', points: [...this.pending.values()] })
		this.pending.clear()
	}

	async connect(request) {
		await this.close()
		const generation = this.generation
		const station = stationOrigin(request.station)
		const password = String(request.password ?? '')
		if (!request.username || !password) throw new BaskStreamError('bad_request', 'Enter the username and password.')
		const client = await BaskStreamClient.connect({
			station,
			username: String(request.username),
			// Kept only in this closure, in memory, so reconnects can log in again.
			password: () => password,
			verifyTls: !request.allowSelfSigned,
			reconnect: true,
			timeoutMs: 20000,
		})
		// The game gave up (or went away) while the login was in flight.
		if (generation !== this.generation || this.socket.readyState !== WebSocket.OPEN) {
			client.close()
			throw new BaskStreamError('connection_closed', 'The connection was cancelled.')
		}
		this.client = client
		this.info = {
			name: str(request.name) ?? new URL(station).host,
			station,
			username: String(request.username),
			apiVersion: str(client.capabilities.apiVersion),
			writesEnabled: client.capabilities.writesEnabled === true,
		}
		client.on('disconnected', () => this.status('reconnecting', 'Connection lost. Reconnecting…'))
		client.on('reconnecting', ({ attempt, delayMs }) => this.status('reconnecting', `Reconnecting (attempt ${attempt}, next in ${Math.round(delayMs / 1000)} s)…`))
		client.on('reconnected', () => this.status('connected'))
		client.on('revoked', () => this.status('connected', 'The station revoked some live subscriptions.'))
		// Required: an unhandled 'error' event would end the process.
		client.on('error', (error) => this.status('connected', friendly(error)))
		return { info: this.info }
	}

	requireClient() {
		if (!this.client) throw new BaskStreamError('not_connected', 'Not connected to a station.')
		return this.client
	}

	async setWatch(points) {
		const client = this.requireClient()
		let ords = [...new Set((points ?? []).map((ord) => toSlotOrd(String(ord))))].filter(Boolean)
		let truncated = false
		if (ords.length > MAX_LIVE_POINTS) {
			ords = ords.slice(0, MAX_LIVE_POINTS)
			truncated = true
		}
		// Serialize watch changes so quick edits apply in order.
		this.watchUpdate = this.watchUpdate.catch(() => {}).then(async () => {
			if (!this.watch) {
				if (!ords.length) return []
				this.watch = await client.watch(ords, { group: `brick-bas-${process.pid}-${Math.random().toString(36).slice(2, 8)}`, leaseSec: 120 })
				this.watch.on('change', (snapshot) => this.queueValue(snapshot))
				return [...this.watch.values.values()]
			}
			return await this.watch.update(ords)
		})
		const snapshots = await this.watchUpdate
		return { points: (snapshots ?? []).map(toValue), truncated }
	}

	async handle(request) {
		switch (request.op) {
			case 'ping':
				return {}
			case 'connect':
				return await this.connect(request)
			case 'disconnect':
				await this.close()
				return {}
			case 'browse': {
				const node = await this.requireClient().browse(str(request.ord) ?? 'slot:/', { depth: 1, metadata: 'none' })
				return { node: toNode(node), children: (node.children ?? []).map(toNode) }
			}
			case 'search': {
				const limit = Math.min(Math.max(Number(request.limit) || 100, 1), 500)
				const reply = await this.requireClient().search('slot:/', String(request.query ?? ''), { limit, metadata: 'none' })
				const result = reply.result ?? {}
				return { nodes: (Array.isArray(result.nodes) ? result.nodes : []).map(toNode), truncated: result.truncated === true }
			}
			case 'describe':
				return { node: toNode(await this.requireClient().describe(String(request.ord), 'full')) }
			case 'read':
				return { points: (await this.requireClient().read((request.points ?? []).slice(0, 1000).map(String))).map(toValue) }
			case 'watch':
				return await this.setWatch(request.points)
			case 'history': {
				const end = Date.now()
				const span = Math.min(Math.max(Number(request.hours) || 4, 1), 24 * 31) * 3600000
				const interval = Math.max(60000, Math.round(span / 120))
				try {
					const rollup = await this.requireClient().historyRollup(String(request.ord), { start: end - span, end, interval })
					const history = (rollup.rollup?.histories ?? rollup.histories ?? [])[0]
					const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
					return { buckets: (history?.buckets ?? []).map((b) => ({ t: Number(b.start), avg: num(b.avg), min: num(b.min), max: num(b.max) })) }
				} catch (error) {
					if (error instanceof BaskStreamError && /history|not_found|unsupported/.test(error.code)) return { buckets: [] }
					throw error
				}
			}
			case 'alarms': {
				const result = await this.requireClient().alarms({ scope: 'open', order: 'newest', limit: 200 })
				const list = result.alarms?.alarms ?? result.alarms ?? []
				return {
					alarms: (Array.isArray(list) ? list : []).map((alarm) => ({
						uuid: String(alarm.uuid),
						timestamp: typeof alarm.timestamp === 'number' ? alarm.timestamp : null,
						priority: typeof alarm.priority === 'number' ? alarm.priority : null,
						alarmClass: str(alarm.alarmClass),
						sourceState: str(alarm.sourceState),
						ackState: str(alarm.ackState),
						source: Array.isArray(alarm.sources) && alarm.sources[0] ? toSlotOrd(String(alarm.sources[0])) : null,
						message: str(alarm.data?.msgText) ?? str(alarm.message) ?? 'Alarm',
					})),
				}
			}
		}
		throw new BaskStreamError('unsupported_op', `${request.op} isn't available on the read-only bridge.`)
	}

	async close() {
		this.generation += 1
		if (this.flushTimer) clearTimeout(this.flushTimer)
		this.flushTimer = null
		this.pending.clear()
		const watch = this.watch
		const client = this.client
		this.watch = null
		this.client = null
		this.info = null
		await watch?.close().catch(() => {})
		client?.close()
	}
}

export function startBridge({ host = HOST, port = PORT } = {}) {
	const server = http.createServer((request, response) => {
		if (request.method === 'GET' && request.url === '/health') {
			response.writeHead(200, { 'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8' })
			response.end(JSON.stringify({ service: 'brick-bas-baskstream-bridge', ok: true, sdk: '@basidekick/baskstream' }))
			return
		}
		response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' })
		response.end('Not found')
	})
	// Web pages always send an Origin; the game doesn't. Refusing them keeps a
	// page in the user's browser from driving this local bridge.
	const sockets = new WebSocketServer({ server, path: '/baskstream', maxPayload: 1024 * 1024, verifyClient: (info) => !info.origin })
	sockets.on('connection', (socket) => {
		const session = new Session(socket)
		socket.on('message', async (payload, isBinary) => {
			let request
			try {
				if (isBinary) throw new Error('binary')
				request = JSON.parse(payload.toString('utf8'))
				if (typeof request !== 'object' || request === null) throw new Error('shape')
			} catch {
				session.send({ op: 'error', code: 'bad_request', message: 'Expected JSON text frames.' })
				return
			}
			const id = request.id ?? null
			if (!OPS.has(request.op)) {
				session.send({ op: 'error', id, code: 'unsupported_op', message: `${String(request.op)} isn't available on the read-only bridge.` })
				return
			}
			if (request.op === 'hello') {
				session.authenticated = !TOKEN || request.token === TOKEN
				session.send(session.authenticated ? { op: 'hello_result', id, readOnly: true } : { op: 'error', id, code: 'forbidden', message: 'Wrong bridge token.' })
				if (!session.authenticated) socket.close(1008, 'Wrong token')
				return
			}
			if (!session.authenticated) {
				session.send({ op: 'error', id, code: 'forbidden', message: 'Say hello with the bridge token first.' })
				return
			}
			try {
				const result = await session.handle(request)
				session.send({ op: `${request.op}_result`, id, ...result })
			} catch (error) {
				session.send({ op: 'error', id, code: error instanceof BaskStreamError ? error.code : 'bridge_error', message: friendly(error) })
			}
		})
		socket.on('close', () => void session.close())
		socket.on('error', () => void session.close())
	})
	return new Promise((resolve, reject) => {
		server.once('error', reject)
		server.listen(port, host, () => resolve({ server, sockets, port: server.address().port, close: () => new Promise((done) => { for (const client of sockets.clients) client.terminate(); server.close(() => done()) }) }))
	})
}

// Run as a program (not imported by a test)? Compare real paths: the module
// URL is percent-encoded and symlinks resolve differently.
export function isMain(moduleUrl) {
	try {
		return realpathSync(fileURLToPath(moduleUrl)) === realpathSync(process.argv[1] ?? '')
	} catch {
		return false
	}
}

if (isMain(import.meta.url)) {
	const bridge = await startBridge()
	// First stdout line is for the game (which may have asked for port 0).
	console.log(JSON.stringify({ ready: true, port: bridge.port, url: `ws://${HOST}:${bridge.port}/baskstream`, readOnly: true }))
	// Started by the game with --owned: the game holds our stdin, so when the
	// game quits (or crashes) the pipe closes and the bridge goes with it.
	if (process.argv.includes('--owned')) {
		process.stdin.on('end', () => process.exit(0))
		process.stdin.on('error', () => process.exit(0))
		process.stdin.resume()
	}
}
