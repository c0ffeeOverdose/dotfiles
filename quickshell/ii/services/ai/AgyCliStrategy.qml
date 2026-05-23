import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    property string prompt: ""
    property string attachmentPath: ""
    property string agyBinary: ""
    property string userSystemPrompt: ""
    property string turnId: ""
    property string hydrationTranscript: ""
    property string modelLabel: ""

    function buildEndpoint(model: AiModel): string {
        return "agy"
    }

    function wrapCdata(value: string): string {
        return "<![CDATA[\n" + value.split("]]>").join("]]]]><![CDATA[>") + "\n]]>"
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        agyBinary = CF.FileUtils.trimFileProtocol(model.endpoint)
        attachmentPath = filePath ? CF.FileUtils.trimFileProtocol(filePath) : ""
        modelLabel = model.model
        userSystemPrompt = systemPrompt
        turnId = `${Date.now().toString(36)}-${Math.random().toString(36).substr(2, 8)}`
        hydrationTranscript = ""

        let latestUserMessage = ""
        let latestUserIndex = -1
        for (let i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role === "user") {
                latestUserMessage = messages[i].rawContent || messages[i].content || ""
                latestUserIndex = i
                break
            }
        }

        if (agyConversationId.length === 0 && latestUserIndex > 0) {
            hydrationTranscript = messages.slice(0, latestUserIndex).map(message => {
                const role = message.role === "assistant" ? "assistant" : "user"
                const content = message.rawContent || message.content || ""
                let rendered = `<message role="${role}">\n${wrapCdata(content)}\n</message>`
                if (message.localFilePath && message.localFilePath.length > 0) {
                    rendered += `\n<attached_local_path>${message.localFilePath}</attached_local_path>`
                }
                return rendered
            }).join("\n")
        }

        const mode = activeMode === "agent" ? "agent" : "chat"
        prompt = `<runtime_context>\n  <active_mode>${mode}</active_mode>\n  <turn_id>${turnId}</turn_id>\n</runtime_context>\n\n<user_request>\n${wrapCdata(latestUserMessage)}\n</user_request>`
        return { "prompt": prompt }
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return ""
    }

    function parseResponseLine(line: string, message: AiMessageData): var {
        const conversationMarkerPrefix = "[[AGY_CONVERSATION_ID:"
        if (line.startsWith(conversationMarkerPrefix) && line.endsWith("]]")) {
            const conversationId = line.slice(conversationMarkerPrefix.length, -2).trim()
            return conversationId.length > 0 ? { "agyConversationId": conversationId } : {}
        }
        if (message.thinking) message.thinking = false
        message.rawContent += line + "\n"
        message.content += line + "\n"
        return {}
    }

    function onRequestFinished(message: AiMessageData): var {
        message.rawContent = message.rawContent.trim()
        message.content = message.content.trim()
        return { "finished": true }
    }

    function reset() {
        prompt = ""
        attachmentPath = ""
        agyBinary = ""
        userSystemPrompt = ""
        turnId = ""
        hydrationTranscript = ""
        modelLabel = ""
    }

    function finalizeScriptContent(scriptContent: string): string {
        const escapedPrompt = CF.StringUtils.shellSingleQuoteEscape(prompt)
        const escapedAttachmentPath = CF.StringUtils.shellSingleQuoteEscape(attachmentPath)
        const escapedAgyBinary = CF.StringUtils.shellSingleQuoteEscape(agyBinary)
        const escapedConversationId = CF.StringUtils.shellSingleQuoteEscape(agyConversationId)
        const escapedContractPath = CF.StringUtils.shellSingleQuoteEscape(CF.FileUtils.trimFileProtocol(agyContractPath))
        const escapedAgyHomePath = CF.StringUtils.shellSingleQuoteEscape(CF.FileUtils.trimFileProtocol(agyHomePath))
        const escapedModelLabel = CF.StringUtils.shellSingleQuoteEscape(modelLabel)
        const escapedUserSystemPrompt = CF.StringUtils.shellSingleQuoteEscape(userSystemPrompt)
        const escapedTurnId = CF.StringUtils.shellSingleQuoteEscape(turnId)
        const escapedHydrationTranscript = CF.StringUtils.shellSingleQuoteEscape(hydrationTranscript)

        return `#!/usr/bin/env bash
set -u

PROMPT_FILE="$(mktemp)"
ERROR_FILE="$(mktemp)"
STDOUT_FILE="$(mktemp)"
cleanup() {
    rm -f "$PROMPT_FILE" "$ERROR_FILE" "$STDOUT_FILE"
}
trap cleanup EXIT

CONVERSATION_ID='${escapedConversationId}'
CONTRACT_PATH='${escapedContractPath}'
AGY_HOME_PATH='${escapedAgyHomePath}'
MODEL_LABEL='${escapedModelLabel}'
USER_SYSTEM_PROMPT='${escapedUserSystemPrompt}'
TURN_ID='${escapedTurnId}'
HYDRATION_TRANSCRIPT='${escapedHydrationTranscript}'
SOURCE_HOME="\${HOME:-}"

ensure_agy_dest() {
    case "$1" in
        "$AGY_HOME_PATH"/*) return 0 ;;
        *) return 1 ;;
    esac
}

sync_agy_file() {
    local source_path="$1"
    local dest_path="$2"
    [ -f "$source_path" ] || return 0
    ensure_agy_dest "$dest_path" || return 0
    mkdir -p "$(dirname "$dest_path")"
    cp -a "$source_path" "$dest_path"
}

sync_agy_skills() {
    local dest_path="$1"
    ensure_agy_dest "$dest_path" || return 0
    local tmp_path="$dest_path.tmp"
    rm -rf "$tmp_path"
    mkdir -p "$tmp_path"

    local copied=0
    local source_dir skill_dir skill_name target_dir
    for source_dir in "$SOURCE_HOME/.agents/skills" "$SOURCE_HOME/.gemini/antigravity/skills" "$SOURCE_HOME/.gemini/antigravity-cli/skills"; do
        [ -d "$source_dir" ] || continue
        for skill_dir in "$source_dir"/*; do
            [ -d "$skill_dir" ] || continue
            [ -f "$skill_dir/SKILL.md" ] || continue
            skill_name="$(basename "$skill_dir")"
            target_dir="$tmp_path/$skill_name"
            rm -rf "$target_dir"
            cp -a "$skill_dir" "$target_dir"
            copied=1
        done
    done

    if [ "$copied" -eq 1 ]; then
        mkdir -p "$(dirname "$dest_path")"
        rm -rf "$dest_path"
        mv "$tmp_path" "$dest_path"
    else
        rm -rf "$tmp_path"
    fi
}

if [ -n "$AGY_HOME_PATH" ]; then
    mkdir -p "$AGY_HOME_PATH/.gemini/antigravity-cli"
    if [ -n "$SOURCE_HOME" ]; then
        sync_agy_skills "$AGY_HOME_PATH/.gemini/antigravity/skills"
        sync_agy_file "$SOURCE_HOME/.gemini/antigravity/mcp_config.json" "$AGY_HOME_PATH/.gemini/antigravity/mcp_config.json"
        sync_agy_file "$SOURCE_HOME/.gemini/config/mcp_config.json" "$AGY_HOME_PATH/.gemini/config/mcp_config.json"
    fi
    export HOME="$AGY_HOME_PATH"
fi

SETTINGS_FILE="$HOME/.gemini/antigravity-cli/settings.json"
if [ -n "$MODEL_LABEL" ]; then
    if command -v jq >/dev/null 2>&1; then
        if [ -f "$SETTINGS_FILE" ]; then
            jq --arg model "$MODEL_LABEL" '.model = $model | .enableTelemetry = false | .permissions.allow = ([.permissions.allow[]?] + ["command(ls)", "command(cat)"] | unique)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" 2>/dev/null && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        else
            jq -n --arg model "$MODEL_LABEL" '{enableTelemetry: false, model: $model, permissions: {allow: ["command(ls)", "command(cat)"]}}' > "$SETTINGS_FILE"
        fi
    elif [ ! -f "$SETTINGS_FILE" ]; then
        printf '{\n  "enableTelemetry": false,\n  "model": "%s",\n  "permissions": {\n    "allow": [\n      "command(ls)",\n      "command(cat)"\n    ]\n  }\n}\n' "$MODEL_LABEL" > "$SETTINGS_FILE"
    fi
fi

if [ -z "$CONVERSATION_ID" ]; then
    if [ ! -f "$CONTRACT_PATH" ]; then
        printf '**Antigravity CLI error**\n\n~~~text\nAGY sidebar contract prompt was not found: %s\n~~~\n' "$CONTRACT_PATH"
        exit 1
    fi
    {
        cat "$CONTRACT_PATH"
        if [ -n "$USER_SYSTEM_PROMPT" ]; then
            printf '\n\n<user_system_prompt>\n%s\n</user_system_prompt>' "$USER_SYSTEM_PROMPT"
        fi
        if [ -n "$HYDRATION_TRANSCRIPT" ]; then
            printf '\n\n<conversation_transcript>\n%s\n</conversation_transcript>' "$HYDRATION_TRANSCRIPT"
        fi
        printf '\n\n%s' '${escapedPrompt}'
    } > "$PROMPT_FILE"
else
    printf '%s' '${escapedPrompt}' > "$PROMPT_FILE"
fi

ATTACHMENT_PATH='${escapedAttachmentPath}'
if [ -n "$ATTACHMENT_PATH" ]; then
    {
        printf '\n\n<attached_file>\n'
        printf '<path>%s</path>\n' "$ATTACHMENT_PATH"
        if [ -f "$ATTACHMENT_PATH" ]; then
            MIME_TYPE="$(file -b --mime-type "$ATTACHMENT_PATH" 2>/dev/null || true)"
            ENCODING="$(file -b --mime-encoding "$ATTACHMENT_PATH" 2>/dev/null || true)"
            printf '<mime_type>%s</mime_type>\n' "\${MIME_TYPE:-unknown}"
            case "$MIME_TYPE:$ENCODING" in
                text/*:*|application/json:*|application/javascript:*|application/xml:*|application/x-sh:*|*:utf-8|*:us-ascii)
                    printf '<content><![CDATA[\n'
                    cat "$ATTACHMENT_PATH"
                    printf '\n]]></content>\n'
                    ;;
                *)
                    printf '<note>Binary or non-text file. Use the local path above if you need to inspect it.</note>\n'
                    ;;
            esac
        else
            printf '<note>File not found.</note>\n'
        fi
        printf '</attached_file>\n'
    } >> "$PROMPT_FILE"
fi

export NO_COLOR=1
export TERM="\${TERM:-dumb}"
AGY_TIMEOUT="\${AGY_TIMEOUT:-180s}"

AGY_BIN="\${AGY_BIN:-${escapedAgyBinary}}"
if [ ! -x "$AGY_BIN" ]; then
    AGY_BIN="$(command -v agy || true)"
fi

if [ -z "$AGY_BIN" ]; then
    printf '**Antigravity CLI error**\n\n~~~text\nagy was not found. Expected it at ${escapedAgyBinary} or in PATH.\n~~~\n'
    exit 127
fi

if [ -n "$CONVERSATION_ID" ]; then
    timeout "$AGY_TIMEOUT" "$AGY_BIN" --conversation "$CONVERSATION_ID" --prompt "$(cat "$PROMPT_FILE")" < /dev/null >"$STDOUT_FILE" 2>"$ERROR_FILE"
else
    timeout "$AGY_TIMEOUT" "$AGY_BIN" --prompt "$(cat "$PROMPT_FILE")" < /dev/null >"$STDOUT_FILE" 2>"$ERROR_FILE"
fi
exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    printf '\n**Antigravity CLI error**\n\n~~~text\n'
    if [ "$exit_code" -eq 124 ]; then
        printf 'agy timed out after %s\n' "$AGY_TIMEOUT"
    fi
    cat "$ERROR_FILE"
    printf '\n~~~\n'
    if [ -s "$STDOUT_FILE" ]; then
        printf '\n~~~text\n'
        cat "$STDOUT_FILE"
        printf '\n~~~\n'
    fi
    exit 0
fi

BRAIN_ROOT="$HOME/.gemini/antigravity-cli/brain"
TRANSCRIPT_PATH=""
if [ -n "$CONVERSATION_ID" ]; then
    TRANSCRIPT_PATH="$BRAIN_ROOT/$CONVERSATION_ID/.system_generated/logs/transcript.jsonl"
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    if [ -d "$BRAIN_ROOT" ]; then
        while IFS= read -r candidate; do
            if grep -Fq "$TURN_ID" "$candidate" 2>/dev/null; then
                TRANSCRIPT_PATH="$candidate"
                CONVERSATION_DIR="$(dirname "$(dirname "$(dirname "$candidate")")")"
                CONVERSATION_ID="$(basename "$CONVERSATION_DIR")"
                break
            fi
        done < <(find "$BRAIN_ROOT" -path '*/.system_generated/logs/transcript.jsonl' -type f 2>/dev/null)
    fi
fi

if [ -n "$CONVERSATION_ID" ]; then
    printf '[[AGY_CONVERSATION_ID:%s]]\n' "$CONVERSATION_ID"
fi

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && command -v jq >/dev/null 2>&1; then
    LATEST_CONTENT="$(jq -r -s '[.[] | select(.source == "MODEL" and (.content // "") != "")][-1].content // ""' "$TRANSCRIPT_PATH" 2>/dev/null || true)"
    if [ -n "$LATEST_CONTENT" ]; then
        printf '%s\n' "$LATEST_CONTENT"
        exit 0
    fi
fi

printf '**Antigravity CLI error**\n\n~~~text\nCould not read the latest AGY transcript response. Falling back to raw agy stdout.\n~~~\n'
cat "$STDOUT_FILE"
`
    }
}
