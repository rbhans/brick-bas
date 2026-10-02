// The read-only bridge, end to end through the real SDK against the demo station.
//   node --test tests/bridge.test.mjs
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { after, before, test } from 'node:test'
import { WebSocket } from 'ws'
import { BaskStreamClient } from '@basidekick/baskstream'
import { PASSWORD, USER, startDemoStation } from '../tools/demo_station.mjs'

process.env.BRICK_BAS_BRIDGE_TOKEN = 'test-token'
const { startBridge } = await import('../scripts/baskstream-bridge.mjs')

let station
let bridge

before(async () => {
	station = await startDemoStation({ covMs: 150 })
	bridge = await startBridge({ port: 0 })
})

after(async () => {
	await bridge.close()
	await station.close()
})

// A tiny client like the game's: request/reply by id, plus pushed frames.
function open(headers = {}) {
	const socket = new WebSocket(`ws://127.0.0.1:${bridge.port}/baskstream`, { headers })
	const pending = new Map()
	const pushes = []
	let serial = 0
	socket.on('message', (data) => {
		const frame = JSON.parse(data.toString())
		if (frame.id && pending.has(frame.id)) {
			pending.get(frame.id)(frame)
			pending.delete(frame.id)
		} else pushes.push(frame)
	})
	const ready = new Promise((resolve, reject) => {
		socket.once('open', resolve)
		socket.once('error', reject)
		socket.once('unexpected-response', (_req, res) => reject(new Error(`HTTP ${res.statusCode}`)))
	})
	const call = (op, fields = {}) =>
		new Promise((resolve) => {
			const id = `${op}-${++serial}`
			pending.set(id, resolve)
			socket.send(JSON.stringify({ op, id, ...fields }))
		})
	return { socket, ready, call, pushes }
}

async function connected() {
	const client = open()
	await client.ready
	assert.equal((await client.call('hello', { token: 'test-token' })).op, 'hello_result')
	const reply = await client.call('connect', { station: station.url, username: USER, password: PASSWORD, allowSelfSigned: false, name: 'Demo' })
	assert.equal(reply.op, 'connect_result', JSON.stringify(reply))
	return client
}

test('logs in through the SDK and reports the station', async () => {
	const client = await connected()
	const status = client.pushes.find((frame) => frame.op === 'status')
	assert.equal(status, undefined, 'no status noise on a clean connect')
	const reply = await client.call('ping')
	assert.equal(reply.op, 'ping_result')
	assert.ok(station.state.logins >= 1)
	client.socket.close()
})

test('browses the tree and searches for points', async () => {
	const client = await connected()
	const root = await client.call('browse', { ord: 'slot:/' })
	assert.equal(root.op, 'browse_result')
	assert.deepEqual(root.children.map((node) => node.name), ['Drivers', 'Services'])
	const network = await client.call('browse', { ord: 'slot:/Drivers/BacnetNetwork' })
	assert.ok(network.children.some((node) => node.name === 'VAV_101' && node.hasChildren))
	assert.ok(network.children.every((node) => node.ord.startsWith('slot:/')), 'ORDs come back as slot paths')
	const found = await client.call('search', { query: 'SpaceTemp', limit: 10 })
	assert.equal(found.op, 'search_result')
	assert.equal(found.nodes.length, 3)
	assert.ok(found.nodes.every((node) => node.kind === 'point'))
	client.socket.close()
})

test('reads values with units and watches them live', async () => {
	const client = await connected()
	const ords = ['slot:/Drivers/BacnetNetwork/VAV_101/points/SpaceTemp', 'slot:/Drivers/BacnetNetwork/VAV_101/points/DamperPos']
	const read = await client.call('read', { points: ords })
	assert.equal(read.points.length, 2)
	assert.equal(read.points[0].units, '°F')
	assert.equal(typeof read.points[0].value, 'number')
	const watched = await client.call('watch', { points: ords })
	assert.equal(watched.op, 'watch_result', JSON.stringify(watched))
	await new Promise((resolve) => setTimeout(resolve, 700))
	const values = client.pushes.filter((frame) => frame.op === 'values').flatMap((frame) => frame.points)
	assert.ok(values.some((value) => value.point === ords[0]), 'COV pushes arrive for watched points')
	const narrowed = await client.call('watch', { points: [ords[1]] })
	assert.equal(narrowed.op, 'watch_result')
	assert.ok([...station.state.groups.values()].some((points) => points.length === 1), 'the watch follows the new point set')
	client.socket.close()
})

test('history and alarms', async () => {
	const client = await connected()
	const history = await client.call('history', { ord: 'slot:/Drivers/BacnetNetwork/AHU_1/points/SupplyAirTemp', hours: 2 })
	assert.equal(history.op, 'history_result')
	assert.ok(history.buckets.length > 10 && typeof history.buckets[0].avg === 'number')
	const alarms = await client.call('alarms')
	assert.equal(alarms.op, 'alarms_result')
	assert.equal(alarms.alarms.length, 2)
	assert.ok(alarms.alarms[0].source.startsWith('slot:/'))
	client.socket.close()
})

test('is read-only: writes and alarm acks do not exist here', async () => {
	const client = await connected()
	for (const op of ['write', 'ack_alarms', 'clear_alarms', 'write_schedule', 'apply_model_changes']) {
		const reply = await client.call(op, { point: 'slot:/x', value: 1 })
		assert.equal(reply.op, 'error')
		assert.equal(reply.code, 'unsupported_op')
	}
	assert.equal(station.state.writes ?? 0, 0, 'nothing reached the station')
	client.socket.close()
})

test('needs the token, refuses browser pages and bad logins', async () => {
	const anonymous = open()
	await anonymous.ready
	const refused = await anonymous.call('browse', { ord: 'slot:/' })
	assert.equal(refused.code, 'forbidden')
	anonymous.socket.close()

	const wrong = open()
	await wrong.ready
	assert.equal((await wrong.call('hello', { token: 'nope' })).code, 'forbidden')

	const page = open({ Origin: 'https://evil.example' })
	await assert.rejects(page.ready, /401|403/)

	const client = open()
	await client.ready
	await client.call('hello', { token: 'test-token' })
	const bad = await client.call('connect', { station: station.url, username: USER, password: 'wrong', allowSelfSigned: false })
	assert.equal(bad.op, 'error')
	assert.match(bad.message, /refused|login|password/i)
	const noUrl = await client.call('connect', { station: '', username: USER, password: PASSWORD })
	assert.equal(noUrl.code, 'bad_request')
	const creds = await client.call('connect', { station: 'https://me:pw@station', username: USER, password: PASSWORD })
	assert.equal(creds.code, 'bad_request')
	client.socket.close()
})

test('reconnects after the station drops the connection', async () => {
	const client = await connected()
	const ords = ['slot:/Drivers/BacnetNetwork/VAV_102/points/SpaceTemp']
	await client.call('watch', { points: ords })
	station.dropAll()
	await new Promise((resolve) => setTimeout(resolve, 2500))
	const statuses = client.pushes.filter((frame) => frame.op === 'status').map((frame) => frame.status)
	assert.ok(statuses.includes('reconnecting'), `told the game it's reconnecting (${statuses})`)
	assert.ok(statuses.includes('connected'), 'and that it came back')
	client.pushes.length = 0
	await new Promise((resolve) => setTimeout(resolve, 600))
	assert.ok(client.pushes.some((frame) => frame.op === 'values'), 'live values resume after the reconnect')
	client.socket.close()
})

test('a login that fails after the socket is up leaves no session behind', async () => {
	await new Promise((resolve) => setTimeout(resolve, 300))
	const sockets = station.state.sockets.size
	const call = BaskStreamClient.prototype.call
	BaskStreamClient.prototype.call = function (op, ...rest) {
		if (op === 'capabilities') return Promise.reject(Object.assign(new Error('capabilities refused'), { code: 'forbidden' }))
		return call.call(this, op, ...rest)
	}
	try {
		const client = open()
		await client.ready
		await client.call('hello', { token: 'test-token' })
		const reply = await client.call('connect', { station: station.url, username: USER, password: PASSWORD, allowSelfSigned: false })
		assert.equal(reply.op, 'error', JSON.stringify(reply))
		await new Promise((resolve) => setTimeout(resolve, 300))
		// Left open, it would log in again by itself whenever the station dropped it.
		assert.equal(station.state.sockets.size, sockets, 'the half-open station socket is closed')
		client.socket.close()
	} finally {
		BaskStreamClient.prototype.call = call
	}
})

test('starts as a program from a path with a space in it (and through a symlink)', async () => {
	const dir = mkdtempSync(join(tmpdir(), 'brick bas '))
	const link = join(dir, 'the bridge.mjs')
	symlinkSync(resolve(import.meta.dirname, '../scripts/baskstream-bridge.mjs'), link)
	const child = spawn(process.execPath, [link, '--port=0', '--owned'], { stdio: ['pipe', 'pipe', 'inherit'] })
	try {
		const line = await new Promise((done, fail) => {
			let text = ''
			child.stdout.on('data', (chunk) => {
				text += chunk
				if (text.includes('\n')) done(text.split('\n')[0])
			})
			child.once('exit', (code) => fail(new Error(`exited ${code} before it was ready`)))
			setTimeout(() => fail(new Error('no ready line')), 5000)
		})
		const ready = JSON.parse(line)
		assert.equal(ready.ready, true)
		assert.ok(ready.port > 0)
		const exited = new Promise((done) => child.once('exit', done))
		child.stdin.end()
		await exited
	} finally {
		child.kill()
		rmSync(dir, { recursive: true, force: true })
	}
})
