// A stand-in Niagara station with the baskStream service, for trying Live mode and for
// tests: Niagara's SCRAM web login, /stream/health and the /stream WebSocket (MessagePack)
// with browse, search, read, leased subscriptions with COV pushes, history rollups and
// alarms. Its points are a small VAV system whose values move like a real one.
//
// Adapted from the baskStream SDK's test station (github.com/rbhans/bask-stream,
// sdk/test/fake-station.mjs, Apache-2.0).
//
//   node tools/demo_station.mjs [--port=8790]     user "operator", password "brick-bas-demo"

import crypto from 'node:crypto'
import { realpathSync } from 'node:fs'
import http from 'node:http'
import { fileURLToPath } from 'node:url'
import { decode, encode } from '@msgpack/msgpack'
import { WebSocketServer } from 'ws'

export const USER = 'operator'
export const PASSWORD = 'brick-bas-demo'
const SALT = crypto.randomBytes(16)
const ITERATIONS = 4096

// --- The station's tree: an AHU and three VAVs under a BACnet network ----------------------

const folder = (name, children) => ({ name, kind: 'container', typeSpec: 'baja:Folder', children })
const device = (name, children) => ({ name, kind: 'component', typeSpec: 'bacnet:BacnetDevice', children })
const point = (name, units, wave, extra = {}) => ({ name, kind: 'point', typeSpec: extra.bool ? 'control:BooleanPoint' : 'control:NumericPoint', units, wave, ...extra })

// wave(t, i): value at time t (s) for the unit's index i, so each VAV differs a little.
const DEVICES = {
	AHU_1: [
		point('SupplyFanSpd', '%', (t) => 62 + 9 * Math.sin(t / 900)),
		point('SupplyFanCmd', null, () => true, { bool: true }),
		point('SupplyAirTemp', '°F', (t) => 55.4 + 0.6 * Math.sin(t / 300)),
		point('SupplyAirTempSp', '°F', () => 55),
		point('ReturnAirTemp', '°F', (t) => 73.2 + 0.4 * Math.sin(t / 1200)),
		point('MixedAirTemp', '°F', (t) => 66 + 1.5 * Math.sin(t / 1500)),
		point('OutsideAirDmprPos', '%', (t) => 28 + 6 * Math.sin(t / 1800)),
		point('ChwVlvPos', '%', (t) => 48 + 15 * Math.sin(t / 700)),
		point('HwVlvPos', '%', () => 0),
		point('DuctStaticPress', 'inH₂O', (t) => 1.0 + 0.05 * Math.sin(t / 200)),
		point('FilterDp', 'inH₂O', () => 0.42),
	],
	VAV_101: vavPoints(0),
	VAV_102: vavPoints(1),
	VAV_103: vavPoints(2),
}

function vavPoints(i) {
	return [
		point('SpaceTemp', '°F', (t) => 72.4 + 0.8 * i + 0.6 * Math.sin(t / 600 + i)),
		point('ClgSetpoint', '°F', () => 74),
		point('HtgSetpoint', '°F', () => 70),
		point('DamperPos', '%', (t) => 45 + 20 * i + 15 * Math.sin(t / 400 + i)),
		point('AirflowCFM', 'cfm', (t) => 420 + 140 * i + 90 * Math.sin(t / 400 + i)),
		point('AirflowSp', 'cfm', () => 450 + 140 * i),
		point('ReheatVlvPos', '%', (t) => (i === 2 ? Math.max(0, 30 * Math.sin(t / 500)) : 0)),
		point('DischargeAirTemp', '°F', (t) => 56 + (i === 2 ? Math.max(0, 20 * Math.sin(t / 500)) : 0)),
		point('Occupied', null, () => true, { bool: true }),
	]
}

function buildTree() {
	const tree = {}
	const add = (ord, entry) => {
		tree[ord] = entry
		return ord
	}
	const deviceOrds = Object.entries(DEVICES).map(([name, points]) => {
		const base = `slot:/Drivers/BacnetNetwork/${name}`
		const pointsOrd = `${base}/points`
		const pointOrds = points.map((p) => add(`${pointsOrd}/${p.name}`, p))
		add(pointsOrd, folder('points', pointOrds))
		return add(base, device(name, [pointsOrd]))
	})
	add('slot:/Drivers/BacnetNetwork', folder('BacnetNetwork', deviceOrds))
	add('slot:/Drivers', folder('Drivers', ['slot:/Drivers/BacnetNetwork']))
	add('slot:/Services', folder('Services', []))
	add('slot:/', { name: 'station', kind: 'container', typeSpec: 'baja:Station', children: ['slot:/Drivers', 'slot:/Services'] })
	return tree
}

const TREE = buildTree()

function describe(ord) {
	const entry = TREE[ord]
	if (!entry) return null
	return {
		ord: `local:|station:|${ord}`,
		name: entry.name,
		display: entry.name,
		kind: entry.kind,
		typeSpec: entry.typeSpec,
		hasChildren: Boolean(entry.children?.length),
		writable: false,
		status: '{ok}',
	}
}

function valueOf(ord, now = Date.now()) {
	const entry = TREE[ord]
	if (!entry || entry.kind !== 'point') return { point: ord, ok: false, code: 'invalid_point', message: 'No such point.' }
	const raw = entry.wave(now / 1000)
	const value = entry.bool ? Boolean(raw) : Math.round(raw * 100) / 100
	return {
		point: ord,
		ok: true,
		valueType: entry.bool ? 'boolean' : 'numeric',
		value,
		displayValue: entry.bool ? (value ? 'true' : 'false') : `${value.toFixed(1)}${entry.units ? ' ' + entry.units : ''}`,
		status: '{ok}',
		timestamp: now,
		facets: entry.units ? { units: entry.units } : {},
	}
}

const ALARMS = [
	{ uuid: 'demo-1', timestamp: Date.now() - 420000, priority: 50, alarmClass: 'Critical', sourceState: 'offnormal', ackState: 'unacked', sources: ['local:|station:|slot:/Drivers/BacnetNetwork/VAV_103/points/SpaceTemp'], data: { msgText: 'VAV_103 space temperature high' } },
	{ uuid: 'demo-2', timestamp: Date.now() - 7200000, priority: 150, alarmClass: 'Maintenance', sourceState: 'offnormal', ackState: 'acked', sources: ['local:|station:|slot:/Drivers/BacnetNetwork/AHU_1/points/FilterDp'], data: { msgText: 'AHU_1 filter due for change' } },
]

export async function startDemoStation({ port = 0, host = '127.0.0.1', covMs = 1000 } = {}) {
	const sessions = new Set()
	const scram = new Map()
	const state = { sockets: new Set(), groups: new Map(), logins: 0, requests: [] }
	const salted = crypto.pbkdf2Sync(PASSWORD, SALT, ITERATIONS, 32, 'sha256')
	const hmac = (key, text) => crypto.createHmac('sha256', key).update(text).digest()
	const cookieOf = (req) => /JSESSIONID=([^;]+)/.exec(req.headers.cookie ?? '')?.[1]

	const server = http.createServer(async (req, res) => {
		let body = ''
		for await (const chunk of req) body += chunk
		let sid = cookieOf(req)
		if (!sid) {
			sid = crypto.randomUUID()
			res.setHeader('Set-Cookie', `JSESSIONID=${sid}; Path=/; HttpOnly`)
		}
		if (req.url === '/stream/health') {
			if (!sessions.has(sid)) return void res.writeHead(302, { Location: '/prelogin' }).end()
			return void res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ service: 'BASkStreamService', ok: true, apiVersion: '1.7' }))
		}
		if (req.url === '/prelogin') return void res.writeHead(200).end('<html>login</html>')
		if (req.url === '/login') return void res.writeHead(200).end('<form action="j_security_check">')
		if (req.url === '/j_security_check/' && req.method === 'GET') {
			if (scram.get(sid)?.done) sessions.add(sid)
			return void res.writeHead(200).end('ok')
		}
		if (req.url === '/j_security_check/') {
			const params = new URLSearchParams(body.replace(/\+/g, '%2B'))
			if (params.get('action') === 'sendClientFirstMessage') {
				const bare = params.get('clientFirstMessage').slice(3)
				const clientNonce = /r=([^,]+)/.exec(bare)[1]
				const serverFirst = `r=${clientNonce}${crypto.randomBytes(12).toString('base64')},s=${SALT.toString('base64')},i=${ITERATIONS}`
				scram.set(sid, { bare, serverFirst })
				return void res.writeHead(200).end(serverFirst)
			}
			const pending = scram.get(sid)
			const final = params.get('clientFinalMessage') ?? ''
			if (!pending) return void res.writeHead(403).end('e=no-session')
			const withoutProof = final.slice(0, final.lastIndexOf(',p='))
			const proof = Buffer.from(final.slice(final.lastIndexOf(',p=') + 3), 'base64')
			const auth = `${pending.bare},${pending.serverFirst},${withoutProof}`
			const clientKey = hmac(salted, 'Client Key')
			const signature = hmac(crypto.createHash('sha256').update(clientKey).digest(), auth)
			const expected = Buffer.alloc(32)
			for (let i = 0; i < 32; i += 1) expected[i] = clientKey[i] ^ signature[i]
			if (!proof.equals(expected)) return void res.writeHead(200).end('e=invalid-proof')
			pending.done = true
			state.logins += 1
			return void res.writeHead(200).end(`v=${hmac(hmac(salted, 'Server Key'), auth).toString('base64')}`)
		}
		res.writeHead(404).end()
	})

	const wss = new WebSocketServer({ noServer: true })
	server.on('upgrade', (req, socket, head) => {
		if (req.url !== '/stream' || !sessions.has(cookieOf(req))) {
			socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n')
			return
		}
		wss.handleUpgrade(req, socket, head, (ws) => {
			state.sockets.add(ws)
			ws.groups = new Map()
			ws.on('close', () => state.sockets.delete(ws))
			ws.on('message', (data) => handle(ws, decode(data)))
		})
	})

	const send = (ws, frame) => ws.readyState === 1 && ws.send(encode(frame))
	const slot = (ord) => String(ord).replace(/^local:\|station:\|/, '')

	function handle(ws, request) {
		state.requests.push(request)
		const { op, id } = request
		switch (op) {
			case 'ping':
				return send(ws, { op: 'pong', id })
			case 'capabilities':
				return send(ws, { op: 'capabilities_result', id, capabilities: { apiVersion: '1.7', writesEnabled: false, limits: { heartbeatIntervalSec: 30, maxSubscriptionsPerClient: 500 } } })
			case 'read':
				return send(ws, { op: 'read_result', id, points: (request.points ?? []).map((p) => valueOf(slot(p))) })
			case 'replace_subscriptions': {
				const points = (request.points ?? []).map(slot)
				ws.groups.set(request.group, points)
				state.groups.set(request.group, points)
				return send(ws, { op: 'subscriptions_replaced', id, group: request.group, points: request.points, leaseSec: request.leaseSec })
			}
			case 'renew_subscriptions':
				if (!ws.groups.has(request.group)) return send(ws, { op: 'error', id, code: 'group_not_found', message: 'Subscription group not found.' })
				return send(ws, { op: 'subscriptions_renewed', id, group: request.group })
			case 'release_subscriptions':
				ws.groups.delete(request.group)
				state.groups.delete(request.group)
				return send(ws, { op: 'subscriptions_released', id, group: request.group })
			case 'browse': {
				const base = slot(request.base ?? 'slot:/')
				const node = describe(base)
				if (!node) return send(ws, { op: 'error', id, code: 'bad_reference', message: 'No such component.' })
				return send(ws, { op: 'browse_result', id, node: { ...node, children: (TREE[base].children ?? []).map(describe) } })
			}
			case 'describe': {
				const node = describe(slot(request.ord))
				if (!node) return send(ws, { op: 'error', id, code: 'bad_reference', message: 'No such component.' })
				return send(ws, { op: 'describe_result', id, node })
			}
			case 'search': {
				const query = String(request.query ?? '').toLowerCase().replace(/\*/g, '')
				const limit = Math.min(Number(request.limit) || 100, 500)
				const hits = Object.keys(TREE).filter((ord) => ord !== 'slot:/' && (ord.toLowerCase().includes(query) || TREE[ord].name.toLowerCase().includes(query)))
				return send(ws, { op: 'search_result', id, result: { count: hits.length, truncated: hits.length > limit, nodes: hits.slice(0, limit).map(describe) } })
			}
			case 'read_alarms':
			case 'subscribe_alarms':
				return send(ws, { op: op === 'read_alarms' ? 'alarms_result' : 'alarms_subscribed', id, alarms: { count: ALARMS.length, alarms: ALARMS } })
			case 'read_history_rollup': {
				const buckets = []
				const entry = TREE[slot(request.ord)]
				for (let t = request.start; t < request.end; t += request.interval) {
					const v = entry?.wave ? Number(entry.wave(t / 1000)) : 0
					buckets.push({ start: t, count: 4, min: v - 0.3, max: v + 0.3, sum: v * 4, avg: v, first: v, last: v })
				}
				return send(ws, { op: 'history_rollup_result', id, rollup: { interval: request.interval, histories: [{ historyId: `/demo/${entry?.name ?? 'x'}`, buckets, bucketCount: buckets.length, truncated: false }] } })
			}
			case 'write':
			case 'ack_alarms':
			case 'ack_alarm':
			case 'clear_alarms':
			case 'write_schedule':
				state.writes = (state.writes ?? 0) + 1
				return send(ws, { op: 'error', id, code: 'writes_disabled', message: 'Writes are disabled on this service.' })
			default:
				return send(ws, { op: 'error', id, code: 'unsupported_op', message: `Unsupported op: ${op}` })
		}
	}

	// Change-of-value pushes for every subscribed point.
	const cov = setInterval(() => {
		const now = Date.now()
		for (const ws of state.sockets) {
			const points = [...new Set([...ws.groups.values()].flat())]
			if (points.length) send(ws, { op: 'cov', timestamp: now, points: points.map((p) => valueOf(p, now)) })
		}
	}, covMs)

	await new Promise((resolve) => server.listen(port, host, resolve))
	const address = server.address()
	return {
		url: `http://${host}:${address.port}`,
		port: address.port,
		state,
		dropAll() {
			for (const ws of state.sockets) ws.terminate()
		},
		async close() {
			clearInterval(cov)
			for (const ws of state.sockets) ws.terminate()
			server.closeAllConnections()
			await new Promise((resolve) => server.close(resolve))
		},
	}
}

let main = false
try {
	main = realpathSync(fileURLToPath(import.meta.url)) === realpathSync(process.argv[1] ?? '')
} catch {}
if (main) {
	const portArg = process.argv.find((arg) => arg.startsWith('--port='))
	const station = await startDemoStation({ port: portArg ? Number(portArg.slice(7)) : 8790 })
	console.log(JSON.stringify({ ready: true, url: station.url, user: USER, password: PASSWORD }))
	console.log(`Demo station at ${station.url} · user "${USER}" · password "${PASSWORD}" · Ctrl+C to stop`)
	if (process.argv.includes('--owned')) {
		process.stdin.on('end', () => process.exit(0))
		process.stdin.resume()
	}
}
