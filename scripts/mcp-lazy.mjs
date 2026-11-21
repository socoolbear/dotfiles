#!/usr/bin/env node
// 지연 시작 MCP 프록시 (stdio). 실제 MCP 서버를 세션이 뜰 때가 아니라 첫 도구 호출 때 띄운다.
// 서버가 뜨면서 비밀 값을 꺼내는 경우 (1Password 지문 인증 등), 쓰지도 않는 세션마다 인증 창이 뜨는 것을 막는다.
//
// 사용: mcp-lazy <캐시 키> -- <서버 명령> [인자...]
//
// 동작:
//   - 캐시가 없으면 서버를 바로 띄워 그대로 중계하고, initialize · 목록 (tools/list 등) 응답을 캐시에 적는다
//   - 캐시가 있으면 initialize · 목록 요청에 캐시로 답하고, 그 밖의 첫 요청 (tools/call 등) 이 올 때 서버를 띄운다
//   - 서버의 도구 목록이 바뀌었으면 캐시 파일 (~/.cache/mcp-lazy/) 을 지운다 — 다음 실행이 다시 적는다
// 서버는 MCP_LAZY_CHILD=1 로 실행된다 (실행 스크립트가 자기 자신을 다시 프록시로 감싸지 않게).
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline'

const HANDSHAKE_ID = 'mcp-lazy-handshake'
const METHOD_NOT_FOUND = -32601
const LIST_METHODS = new Set(['tools/list', 'resources/list', 'resources/templates/list', 'prompts/list'])
const EMPTY_LIST_RESULTS = {
  'resources/list': { resources: [] },
  'resources/templates/list': { resourceTemplates: [] },
  'prompts/list': { prompts: [] },
}

const separatorIndex = process.argv.indexOf('--')

if (separatorIndex !== 3 || process.argv.length < 5) {
  console.error('사용: mcp-lazy <캐시 키> -- <서버 명령> [인자...]')
  process.exit(2)
}

const cacheKey = process.argv[2]
const [serverCommand, ...serverArgs] = process.argv.slice(4)
const cacheDir = join(process.env.XDG_CACHE_HOME || join(homedir(), '.cache'), 'mcp-lazy')
const cacheFile = join(cacheDir, `${createHash('sha256').update(cacheKey).digest('hex').slice(0, 16)}.json`)

let cache = readCache()
let server = null
let serverReady = false
let initializeRequest = null
const waitingMessages = [] // 서버가 준비되기 전에 받은 요청
const pendingRequests = new Map() // 서버로 넘긴 요청 id → method
const recorded = { protocolVersion: null, initializeResult: null, lists: {} }

function readCache() {
  try {
    return JSON.parse(readFileSync(cacheFile, 'utf8'))
  } catch {
    return null
  }
}

function writeCache() {
  if (!recorded.initializeResult) {
    return
  }

  try {
    mkdirSync(cacheDir, { recursive: true })
    writeFileSync(cacheFile, JSON.stringify(recorded))
  } catch (error) {
    console.error(`mcp-lazy: 캐시를 쓰지 못했습니다 (${error.message})`)
  }
}

function sendToClient(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`)
}

function sendToServer(message) {
  if (message.id !== undefined && message.method) {
    pendingRequests.set(message.id, message.method)
  }

  server.stdin.write(`${JSON.stringify(message)}\n`)
}

function startServer() {
  server = spawn(serverCommand, serverArgs, {
    stdio: ['pipe', 'pipe', 'inherit'],
    env: { ...process.env, MCP_LAZY_CHILD: '1' },
  })

  server.stdin.on('error', () => {})
  server.on('error', (error) => failPending(`서버를 실행하지 못했습니다: ${error.message}`, 1))
  server.on('exit', (code) => failPending(`서버가 종료됐습니다 (exit ${code})`, code ?? 1))
  createInterface({ input: server.stdout }).on('line', handleServerLine)
}

// 서버가 죽으면 답을 기다리던 요청에 오류로 답하고 끝낸다 (지문 인증을 취소한 경우 등)
function failPending(reason, exitCode) {
  const unanswered = [...pendingRequests.keys(), ...waitingMessages.filter((message) => message.id !== undefined).map((message) => message.id)]

  for (const id of unanswered) {
    sendToClient({ jsonrpc: '2.0', id, error: { code: -32000, message: `mcp-lazy: ${reason}` } })
  }

  process.exit(exitCode)
}

// 캐시로 답해 둔 initialize 를 뒤늦게 띄운 서버와 다시 한다
function wakeServer() {
  if (server) {
    return
  }

  startServer()
  server.stdin.write(`${JSON.stringify({ ...initializeRequest, id: HANDSHAKE_ID })}\n`)
}

function finishHandshake() {
  server.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })}\n`)
  serverReady = true

  for (const message of waitingMessages.splice(0)) {
    sendToServer(message)
  }
}

// 한 쪽에 다 담긴 목록과 "그런 메서드 없음" 오류만 캐시에 적는다 — 일시적인 오류 (DB 연결 실패 등) 는 적지 않는다
function isCacheableListResponse(message) {
  if (message.result) {
    return !message.result.nextCursor
  }

  return message.error?.code === METHOD_NOT_FOUND
}

function recordResponse(message) {
  const method = pendingRequests.get(message.id)

  pendingRequests.delete(message.id)

  if (cache) {
    return
  }

  if (method === 'initialize' && message.result) {
    recorded.initializeResult = message.result
  } else if (LIST_METHODS.has(method) && isCacheableListResponse(message)) {
    recorded.lists[method] = message.result ? { result: message.result } : { error: message.error }
  } else {
    return
  }

  writeCache()
}

function handleServerLine(line) {
  let message

  try {
    message = JSON.parse(line)
  } catch {
    process.stdout.write(`${line}\n`)
    return
  }

  if (message.id === HANDSHAKE_ID) {
    finishHandshake()
    return
  }

  if (message.id !== undefined && !message.method) {
    recordResponse(message)
  }

  process.stdout.write(`${line}\n`)
}

function handleInitialize(message) {
  initializeRequest = message
  recorded.protocolVersion = message.params?.protocolVersion ?? null

  // 캐시가 없거나 다른 프로토콜 버전으로 적힌 것이면 서버를 바로 띄워 새로 적는다
  if (cache?.protocolVersion !== recorded.protocolVersion) {
    cache = null
    startServer()
    serverReady = true
    sendToServer(message)
    return
  }

  sendToClient({ jsonrpc: '2.0', id: message.id, result: cache.initializeResult })
}

function handleClientLine(line) {
  let message

  try {
    message = JSON.parse(line)
  } catch {
    return
  }

  if (message.method === 'initialize') {
    handleInitialize(message)
    return
  }

  if (serverReady) {
    sendToServer(message)
    return
  }

  if (server) {
    waitingMessages.push(message)
    return
  }

  // 여기부터는 캐시로 답하는 동안 (서버를 아직 띄우지 않음)
  if (message.id === undefined) {
    return // 알림 (notifications/initialized · cancelled) 은 서버를 띄울 때 다시 보낸다
  }

  if (message.method === 'ping') {
    sendToClient({ jsonrpc: '2.0', id: message.id, result: {} })
    return
  }

  if (cache?.lists?.[message.method] && !message.params?.cursor) {
    sendToClient({ jsonrpc: '2.0', id: message.id, ...cache.lists[message.method] })
    return
  }

  // 캐시에 못 적은 부가 목록 (DB 연결 실패 · 여러 쪽짜리 resources 등) 은 빈 목록으로 답한다.
  // 서버를 띄우면 세션이 뜰 때마다 비밀값을 읽어 (1Password 승인 창) 지연 시작이 무의미해진다. 도구 목록만은 서버를 띄워서라도 받는다
  if (EMPTY_LIST_RESULTS[message.method]) {
    sendToClient({ jsonrpc: '2.0', id: message.id, result: EMPTY_LIST_RESULTS[message.method] })
    return
  }

  waitingMessages.push(message)
  wakeServer()
}

createInterface({ input: process.stdin })
  .on('line', handleClientLine)
  .on('close', () => {
    server?.kill()
    process.exit(0)
  })

for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) {
  process.on(signal, () => {
    server?.kill()
    process.exit(0)
  })
}
