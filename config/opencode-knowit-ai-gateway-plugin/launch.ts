import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"
import { syncInventory } from "./inventory.ts"

const configHome = process.env.XDG_CONFIG_HOME || join(homedir(), ".config")
const [command, ...args] = process.argv.slice(2)
if (!command) throw new Error("expected an OpenCode command")

const count = await syncInventory(configHome, process.env.AGW_API_KEY || "")
console.error(`knowit-ai-gateway: ${count} models available`)
const child = spawn(command, args, { stdio: "inherit", env: process.env })
for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => child.kill(signal))
child.on("error", (error) => { console.error(error); process.exitCode = 1 })
child.on("exit", (code, signal) => { process.exitCode = code ?? (signal === "SIGINT" ? 130 : 143) })
