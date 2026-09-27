import crypto from 'node:crypto'
import http from 'node:http'
import { decode, encode } from '@msgpack/msgpack'
import { WebSocketServer } from 'ws'

const host = '127.0.0.1'
const port = 8790
const password = 'demo-password'
const sessions = new Map()

const server = http.createServer(async (request, response) => {
	const body = await readBody(request)
	const cookie = sessionCookie(request, response)
	const session = sessions.get(cookie)
	if (request.method === 'GET' && request.url === '/prelogin') return reply(response, 200, 'prelogin')
	if (request.method === 'POST' && request.url === '/login') return reply(response, 200, '<form action="j_security_check"></form>')
	if (request.method === 'POST' && request.url === '/j_security_check/') {
		const form = new URLSearchParams(body)
		if (form.get('action') === 'sendClientFirstMessage') {
			const first = String(form.get('clientFirstMessage') || '').replace(/^n,,/, '')
			const nonce = Object.fromEntries(first.split(',').map(pair))["r"]
			const salt = Buffer.from('brick-bas-test-salt', 'utf8').toString('base64')
			const challenge = `r=${nonce}-server,s=${salt},i=128`
			session.first = first
			session.challenge = challenge
			return reply(response, 200, challenge)
		}
		const final = String(form.get('clientFinalMessage') || '')
		const withoutProof = final.split(',p=')[0]
		const salted = crypto.pbkdf2Sync(Buffer.from(password, 'utf8'), Buffer.from('brick-bas-test-salt', 'utf8'), 128, 32, 'sha256')
		const serverKey = crypto.createHmac('sha256', salted).update('Server Key').digest()
		const authMessage = `${session.first},${session.challenge},${withoutProof}`
		const signature = crypto.createHmac('sha256', serverKey).update(authMessage).digest('base64')
		return reply(response, 200, `v=${signature}`)
	}
	if (request.method === 'GET' && request.url === '/j_security_check/') return reply(response, 200, 'ok')
	if (request.method === 'GET' && request.url === '/stream/health') {
		response.writeHead(200, { 'Content-Type': 'application/json' })
		return response.end(JSON.stringify({ service: 'BASkStreamService', apiVersion: '1.5', ok: true }))
	}
	reply(response, 404, 'Not found')
})

const sockets = new WebSocketServer({ server, path: '/stream' })
sockets.on('connection', (socket) => socket.on('message', (payload, isBinary) => {
	if (!isBinary) return
	const request = decode(payload)
	const base = { id: request.id }
	if (request.op === 'ping') socket.send(encode({ ...base, op: 'pong' }))
	if (request.op === 'capabilities') socket.send(encode({ ...base, op: 'capabilities_result', capabilities: {
		apiVersion: '1.5', operations: ['read', 'replace_subscriptions', 'release_subscriptions'],
		limits: { maxSubscriptionsPerClient: 500, subscriptionLeaseSec: 300 },
		subscriptions: { pointCov: true, viewGroups: true, leasedGroups: true },
	} }))
	if (request.op === 'replace_subscriptions') socket.send(encode({ ...base, op: 'subscriptions_replaced', points: (request.points || []).map((point) => ({
		point, ok: true, value: 62.5, valueType: 'baja:Double', status: '{ok}', facets: { units: '%' }, timestamp: Date.now(),
	})) }))
	if (request.op === 'release_subscriptions') socket.send(encode({ ...base, op: 'subscriptions_replaced', points: [] }))
}))

server.listen(port, host, () => console.log(`Mock BASkStreamService: http://${host}:${port}`))

function pair(value) {
	const index = value.indexOf('=')
	return [value.slice(0, index), value.slice(index + 1)]
}

function sessionCookie(request, response) {
	const existing = String(request.headers.cookie || '').match(/BRICK_TEST=([^;]+)/)?.[1]
	const id = existing || crypto.randomBytes(8).toString('hex')
	if (!sessions.has(id)) sessions.set(id, {})
	if (!existing) response.setHeader('Set-Cookie', `BRICK_TEST=${id}; Path=/; HttpOnly`)
	return id
}

function reply(response, status, body) {
	response.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' })
	response.end(body)
}

function readBody(request) {
	return new Promise((resolve) => {
		const chunks = []
		request.on('data', (chunk) => chunks.push(chunk))
		request.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
	})
}
