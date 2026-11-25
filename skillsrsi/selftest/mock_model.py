#!/usr/bin/env python3
"""假模型服务:没有模型 Key 时用来空跑 SkillsRSI 的流水线。

按剧本回答四类请求(迁移、裁判、诊断、改写),并把每个请求的原文存盘供排查。
只监听本机回环地址,不访问外网。回答里的判断都是占位内容,不代表真实模型的分析。

用法: python3 -I mock_model.py <端口> <存盘目录> <迁移产物文件>
"""
import json
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(sys.argv[1])
STATE = Path(sys.argv[2])
(STATE / "req").mkdir(parents=True, exist_ok=True)
FIXTURE = Path(sys.argv[3]).read_text(encoding="utf8")
OUTPUT = "harmony/entry/src/main/ets/calculator/NumberFormatter.ets"
SKILL = "skills/hmbot-migrate/SKILL.md"
MAX_TURNS = 12

LOCK = threading.Lock()
SEQ = 0


def log(message):
    with LOCK:
        with open(STATE / "log.txt", "a", encoding="utf8") as handle:
            handle.write(time.strftime("%H:%M:%S ") + message + "\n")


def text_of(body):
    parts = []
    for message in body.get("messages") or []:
        content = message.get("content")
        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and isinstance(part.get("text"), str):
                    parts.append(part["text"])
    return "\n".join(parts)


def classify(text, body=None):
    if any((tool.get("function") or {}).get("name") == "submit_analysis" for tool in (body or {}).get("tools") or []
           if isinstance(tool, dict)):
        return "mode-d-tool"  # 0.4.1 起,诊断是模型带工具多轮取证
    if "# 本轮冻结材料及实际取证" in text and "本 API 调用只返回 JSON" in text:
        return "judge"
    if "Return analysis.json directly" in text:
        return "mode-d"
    if 'Return JSON {"files":' in text:
        return "mutate"
    if "This is the bounded OpenCalc formatter migration" in text and "title generator" not in text.lower():
        return "migration"
    return "other"


def tool_call(call_id, name, arguments):
    return {"id": call_id, "type": "function",
            "function": {"name": name, "arguments": json.dumps(arguments, ensure_ascii=False)}}


def pick(tools, candidates):
    for name in candidates:
        if name in tools:
            return name
    return None


def first_key(properties, pattern):
    for key in properties:
        if re.search(pattern, key, re.I):
            return key
    return None


def migration(body):
    """迁移:先加载技能,再写出产物,然后结束。"""
    messages = body.get("messages") or []
    tools = {}
    for tool in body.get("tools") or []:
        function = tool.get("function") if isinstance(tool, dict) else None
        if function and function.get("name"):
            tools[function["name"]] = (function.get("parameters") or {}).get("properties") or {}
    turns = sum(1 for m in messages if m.get("role") == "assistant" and m.get("tool_calls"))
    log("迁移: 工具=%s 已调用轮次=%d" % (sorted(tools), turns))
    if turns == 0:
        name = pick(tools, ["skill"])
        if name is None:  # 不带工具的请求(比如生成会话标题)不该回工具调用
            return "[mock] 迁移任务", []
        properties = tools.get(name, {})
        if "name" in properties:
            arguments = {"name": "hmbot-migrate"}
        elif "skill" in properties:
            arguments = {"skill": "hmbot-migrate"}
        else:
            arguments = {next(iter(properties), "name"): "hmbot-migrate"} if properties else {}
        return None, [tool_call("call_skill_1", name, arguments)]
    if turns == 1:
        name = pick(tools, ["write", "write_file", "create_file", "create", "str_replace_based_edit_tool",
                            "str_replace_editor", "filesystem_write_file"])
        properties = tools.get(name, {})
        if "command" in properties:
            arguments = {"command": "create", first_key(properties, r"path|file"): OUTPUT,
                         first_key(properties, r"text|content|new"): FIXTURE}
        else:
            arguments = {first_key(properties, r"path|file"): OUTPUT, first_key(properties, r"content|text|data"): FIXTURE}
        arguments = {key: value for key, value in arguments.items() if key}
        return None, [tool_call("call_write_1", name, arguments)]
    return "[mock] 迁移结束:已写出 " + OUTPUT, []


def judge(text):
    """裁判:状态照抄机械回放结果,只用于验证流水线。"""
    marker = "# 本轮冻结材料及实际取证\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n本 API 调用只返回 JSON", start)
    observations = json.loads(text[start:end])
    rows = []
    for record in observations.get("replay") or []:
        observed = record.get("observed") or json.dumps(record.get("evidence"), ensure_ascii=False)
        rows.append({"id": record.get("id"), "status": record.get("status", "NOT_RUN"),
                     "observed": "[桩·照抄机械回放] " + str(observed)[:300]})
    for page_id, page in (observations.get("pages") or {}).items():
        reached = page.get("reached") is True
        ok = bool(page.get("foreground_ok")) and reached
        rows.append({"id": page.get("id") or page_id, "status": "PASS" if ok else "FAIL",
                     "observed": "[桩·页面取证] foreground_ok=%s reached=%s texts=%s" % (
                         page.get("foreground_ok"), page.get("reached"), (page.get("texts") or [])[:8])})
    return {"assertions": rows, "notes": "[桩] 状态照抄机械回放与页面取证结果,只用于验证流水线,不是语义裁判。"}


def mode_d(text):
    ids = sorted(set(re.findall(r'"(S\d{3})"\s*:\s*\{', text)))
    evidence = ids[0] if ids else "S001"
    validation = ids[2] if len(ids) > 2 else evidence
    return {"disposition": "actionable", "summary": "[桩] 空跑用的占位诊断,不代表真实分析。",
            "work_items": [{"schema": "skillopt-work-item/2", "id": "w0001", "mode": "B", "target_skill": "hmbot-migrate",
                            "allowed_paths": ["skills/hmbot-migrate"], "attribution_status": "proposed",
                            "symptom": "[stub] placeholder symptom used only for the plumbing test",
                            "expected_behavior": "[stub] placeholder expectation used only for the plumbing test",
                            "reproduction": "[stub] placeholder reproduction used only for the plumbing test",
                            "evidence_ids": [evidence], "validation_ids": [validation]}]}


def mutate(text):
    start = text.rfind('\n{"items":')
    data = json.loads(text[start + 1:]) if start >= 0 else {}
    original = (data.get("files") or {}).get(SKILL)
    if original is None:
        raise ValueError("改写请求里没有 " + SKILL)
    revised = original.rstrip("\n") + "\n\n## Mock revision (plumbing test)\n\nThis paragraph was appended by a scripted mock model to verify the rewrite path; it carries no real guidance.\n"
    return {"files": {SKILL: revised}, "summary": "[桩] 在手册末尾追加了一段占位文字,只为验证改写通路。"}


def mode_d_tool(text):
    """0.4.1 的诊断:第一轮列一下证据,第二轮直接交占位的分析。"""
    ids = sorted(set(re.findall(r'"(S\d{3})"\s*:\s*\{', text)))
    if "Tool actions already taken: []" in text:
        return None, [tool_call("call_list_1", "list", {"prefix": (ids[0] if ids else "S001") + "/"})]
    return None, [tool_call("call_submit", "submit_analysis", {"analysis": mode_d(text)})]


def respond(kind, body, text):
    if kind == "migration":
        return migration(body)
    if kind == "mode-d-tool":
        return mode_d_tool(text)
    if kind == "judge":
        return json.dumps(judge(text), ensure_ascii=False), []
    if kind == "mode-d":
        return json.dumps(mode_d(text), ensure_ascii=False), []
    if kind == "mutate":
        return json.dumps(mutate(text), ensure_ascii=False), []
    return "ok", []


def completion(model, content, calls):
    message = {"role": "assistant", "content": content}
    if calls:
        message["tool_calls"] = calls
    return {"id": "chatcmpl-mock", "object": "chat.completion", "created": 1, "model": model,
            "choices": [{"index": 0, "message": message, "finish_reason": "tool_calls" if calls else "stop"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}


def chunks(model, content, calls):
    def chunk(delta, finish=None):
        return ("data: " + json.dumps({"id": "chatcmpl-mock", "object": "chat.completion.chunk", "created": 1, "model": model,
                                       "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}, ensure_ascii=False) + "\n\n").encode()
    if calls:
        first = calls[0]
        yield chunk({"role": "assistant", "content": None, "tool_calls": [
            {"index": 0, "id": first["id"], "type": "function", "function": {"name": first["function"]["name"], "arguments": ""}}]})
        yield chunk({"tool_calls": [{"index": 0, "function": {"arguments": first["function"]["arguments"]}}]})
        yield chunk({}, "tool_calls")
    else:
        yield chunk({"role": "assistant", "content": ""})
        yield chunk({"content": content or ""})
        yield chunk({}, "stop")
    yield b"data: [DONE]\n\n"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            body = {}
        text = text_of(body)
        kind = classify(text, body)
        global SEQ
        with LOCK:
            SEQ += 1
            number = SEQ
        (STATE / "req" / ("%04d-%s.json" % (number, kind))).write_text(json.dumps(body, ensure_ascii=False, indent=1), encoding="utf8")
        try:
            content, calls = respond(kind, body, text)
        except Exception as error:  # 回答不了就如实报错,方便排查
            log("#%04d %s 回答失败: %r" % (number, kind, error))
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            payload = json.dumps({"error": {"message": "mock failed: %r" % error}}).encode()
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        summary = ("tool_calls=" + ",".join(c["function"]["name"] for c in calls)) if calls else ("text %d 字" % len(content or ""))
        log("#%04d %s stream=%s %s" % (number, kind, bool(body.get("stream")), summary))
        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close")
            self.end_headers()
            for piece in chunks(body.get("model"), content, calls):
                self.wfile.write(piece)
                self.wfile.flush()
            self.close_connection = True
            return
        payload = json.dumps(completion(body.get("model"), content, calls), ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    log("假模型服务启动,端口 %d" % PORT)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
