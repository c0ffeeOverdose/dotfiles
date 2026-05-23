pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    property Component agyCliStrategy: AgyCliStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"
    readonly property string defaultModelId: "agy-gemini-3.5-flash-high"
    readonly property string defaultMode: "chat"
    readonly property string agyHomePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/ai/agy-home`)
    readonly property string agySettingsPath: `${root.agyHomePath}/.gemini/antigravity-cli/settings.json`
    readonly property string agyContractPath: Quickshell.shellPath("services/ai/prompts/agy-sidebar-contract.md")
    property list<string> modeList: ["chat", "agent"]
    property string currentMode: {
        const mode = (Persistent.states?.ai?.mode ?? root.defaultMode).toLowerCase();
        return root.modeList.indexOf(mode) !== -1 ? mode : root.defaultMode;
    }
    readonly property string chatModePrompt: "## Sidebar Mode: Chat\n- You are in Chat mode. Chat with the user and help reason through requests.\n- You may perform read-only file exploration when the user provides a path, attaches a file, or clearly asks you to inspect local files.\n- You may use read-only web tools for web search, Google Search, URL fetch, web fetch, or browser/page fetch when current information or source content is needed.\n- Allowed read-only file operations: read file contents, list directories, glob file paths, and grep/search file contents.\n- Allowed shell commands are limited to `cat`, `ls`, `dir`, `grep`, and `rg` with no pipes, redirects, command substitution, or command chaining. Do not use shell network commands like `curl` or `wget`; use web search/fetch tools instead.\n- Do not create, edit, delete, move, rename, or overwrite files or settings.\n- If the user asks you to modify files, install software, run non-read-only commands, or perform agentic actions, explain that they need to switch to `/mode Agent` first.\n- For Antigravity CLI, treat these rules as strict instructions: only use read/glob/grep/list tools, web search/fetch tools, or the allowed read-only shell commands above."
    readonly property string agentModePrompt: "## Sidebar Mode: Agent\n- You are in Agent mode. You may perform actions, use tools, modify files, and run commands when they are needed for the user's request.\n- Keep actions scoped to the user's request and prefer the smallest correct change.\n- Before running a dangerous or potentially destructive command/action, ask the user for explicit confirmation and wait.\n- Dangerous actions include deleting or overwriting files, bulk moves/renames, sudo/admin commands, package installation/removal, piping network downloads into shells, permission/ownership changes, killing processes, destructive git operations, migrations, secret/credential access, and operations outside the requested scope."
    readonly property string modePrompt: root.currentMode === "agent" ? root.agentModePrompt : root.chatModePrompt
    readonly property string effectiveSystemPrompt: `${root.systemPrompt}\n\n${root.modePrompt}`

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelRequiresApiKey: models[currentModelId]?.requires_key ?? false
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})` 
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string configuredTool: Config?.options.ai.tool ?? "search"
    property string currentTool: {
        const formatTools = root.tools[models[currentModelId]?.api_format] ?? {};
        if (configuredTool in formatTools) return configuredTool;
        return Object.keys(formatTools)[0] ?? "none";
    }
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "agy": {
            "none": []
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] ?? {})
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    function chatReadTools(apiFormat) {
        const commandDescription = "Run one read-only file exploration command. Allowed commands: cat, ls, dir, grep, rg. Use these only to read file contents, list directories, glob file paths, or grep/search file contents. Do not use pipes, redirects, command substitution, command chaining, shell network commands, or commands that modify files/settings.";
        const parameters = {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "A single read-only command, e.g. `cat /path/to/file`, `ls /path`, `rg --files -g '*.qml' /path`, or `grep -R pattern /path`"
                }
            },
            "required": ["command"]
        };

        if (apiFormat === "gemini") {
            return [{"google_search": {}}, {"functionDeclarations": [{
                "name": "run_shell_command",
                "description": commandDescription,
                "parameters": parameters
            }]}];
        }
        if (apiFormat === "openai" || apiFormat === "mistral") {
            return [{
                "type": "function",
                "function": {
                    "name": "run_shell_command",
                    "description": commandDescription,
                    "parameters": parameters
                }
            }];
        }
        return [];
    }

    function effectiveTools(model, toolName) {
        if (root.currentMode === "chat") return root.chatReadTools(model.api_format);
        const formatTools = root.tools[model.api_format] ?? {};
        return formatTools[toolName] ?? [];
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    property var models: Config.options.policies.ai === 2 ? {} : {
        "agy-gemini-3.5-flash-high": aiModelComponent.createObject(this, {
            "name": "Antigravity: Gemini 3.5 Flash (High)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "Gemini 3.5 Flash (High)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "agy-gemini-3.5-flash-medium": aiModelComponent.createObject(this, {
            "name": "Antigravity: Gemini 3.5 Flash (Medium)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "Gemini 3.5 Flash (Medium)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "agy-gemini-3.1-pro-high": aiModelComponent.createObject(this, {
            "name": "Antigravity: Gemini 3.1 Pro (High)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "Gemini 3.1 Pro (High)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "agy-gemini-3.1-pro-low": aiModelComponent.createObject(this, {
            "name": "Antigravity: Gemini 3.1 Pro (Low)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "Gemini 3.1 Pro (Low)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "agy-claude-sonnet-4.6-thinking": aiModelComponent.createObject(this, {
            "name": "Antigravity: Claude Sonnet 4.6 (Thinking)",
            "icon": "spark-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "Claude Sonnet 4.6 (Thinking)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "agy-claude-opus-4.6-thinking": aiModelComponent.createObject(this, {
            "name": "Antigravity: Claude Opus 4.6 (Thinking)",
            "icon": "spark-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "Claude Opus 4.6 (Thinking)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "agy-gpt-oss-120b-medium": aiModelComponent.createObject(this, {
            "name": "Antigravity: GPT-OSS 120B (Medium)",
            "icon": "openai-symbolic",
            "description": Translation.tr("Antigravity CLI | Uses your signed-in Antigravity subscription via agy --prompt"),
            "homepage": "https://antigravity.google/docs/models?id=GoogleAntigravity",
            "endpoint": `${Directories.home}/.local/bin/agy`,
            "model": "GPT-OSS 120B (Medium)",
            "requires_key": false,
            "api_format": "agy",
        }),
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 3 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nPro-level intelligence at the speed and pricing of Flash."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: modelList.indexOf(Persistent.states?.ai?.model) !== -1 ? Persistent.states.ai.model : root.defaultModelId

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
        "agy": agyCliStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.resetAgyConversation();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    FileView {
        id: agySettingsFile
        path: root.agySettingsPath
        watchChanges: false
        blockLoading: true
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            const previousModelId = root.currentModelId;
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            root.currentModelId = modelId;
            if (setPersistentState && previousModelId !== modelId) root.resetAgyConversation();
            if (model.api_format === "agy") root.syncAgyModelSetting(model.model, feedback);
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
        }
    }

    function syncAgyModelSetting(modelLabel, feedback = true) {
        // The AGY request script writes this into the sidebar's isolated HOME.
        // Avoid touching the normal Antigravity TUI settings/history.
    }

    function agyStableUserSystemPrompt() {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        prompt = prompt.split("\r\n").join("\n").split("\n")
            .filter(line => line.indexOf("{DATETIME}") === -1 && line.indexOf("{WINDOWCLASS}") === -1)
            .join("\n").trim();

        const substitutions = {
            "{DISTRO}": SystemInfo.distroName,
            "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`
        };
        for (let key in substitutions) {
            prompt = prompt.split(key).join(substitutions[key]);
        }
        return prompt;
    }

    function resetAgyConversation() {
        if (Persistent.states?.ai) Persistent.states.ai.agyConversationId = "";
    }

    function modeDisplayName(mode = root.currentMode) {
        return mode === "agent" ? "Agent" : "Chat";
    }

    function setMode(mode) {
        if (!mode) mode = "";
        mode = mode.toLowerCase();
        if (root.modeList.indexOf(mode) === -1) {
            root.addMessage(Translation.tr("Invalid mode. Supported: Chat, Agent"), root.interfaceRole);
            return false;
        }
        Persistent.states.ai.mode = mode;
        root.addMessage(Translation.tr("Mode set to %1").arg(root.modeDisplayName(mode)), root.interfaceRole);
        if (mode === "chat" && models[currentModelId]?.api_format === "agy") {
            root.addMessage(Translation.tr("Chat mode restricts AGY by instruction only; the Antigravity CLI has no true no-tools flag."), root.interfaceRole);
        }
        return true;
    }

    function printMode() {
        root.addMessage(Translation.tr("Mode: %1").arg(root.modeDisplayName()), root.interfaceRole);
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
        root.resetAgyConversation();
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.saveChat("lastSession")
            root.responseFinished()
        }

        function makeRequest() {
            const model = models[currentModelId];

            // Fetch API keys if needed
            if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            requester.currentStrategy.activeMode = root.currentMode;
            requester.currentStrategy.agyConversationId = Persistent.states?.ai?.agyConversationId ?? "";
            requester.currentStrategy.agyContractPath = root.agyContractPath;
            requester.currentStrategy.agyHomePath = root.agyHomePath;
            const strategySystemPrompt = model.api_format === "agy" ? root.agyStableUserSystemPrompt() : root.effectiveSystemPrompt;
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, strategySystemPrompt, root.temperature, root.effectiveTools(model, root.currentTool), root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.agyConversationId) {
                        Persistent.states.ai.agyConversationId = result.agyConversationId;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function isAllowedChatReadCommand(command) {
        if (!command || command.length === 0) return false;
        const trimmed = command.trim();
        if (/[\n\r;&|`$<>(){}]/.test(trimmed)) return false;
        const parts = trimmed.split(/\s+/);
        const commandName = parts[0];
        const allowedCommands = ["cat", "ls", "dir", "grep", "rg"];
        if (allowedCommands.indexOf(commandName) === -1) return false;

        if (commandName === "cat") {
            if (parts.length < 2) return false;
            for (let i = 1; i < parts.length; i++) {
                if (parts[i] === "-") return false;
            }
            return true;
        }
        if (commandName === "grep" || commandName === "rg") {
            return parts.length >= 2;
        }
        return true;
    }

    function isDangerousShellCommand(command) {
        if (!command || command.length === 0) return true;
        const lower = command.toLowerCase();
        if (/[\n\r;&|`$<>]/.test(command)) return true;
        if (/(^|\s)(sudo|su|doas|pkexec|rm|rmdir|mv|cp|dd|mkfs|mount|umount|chmod|chown|chgrp|kill|pkill|killall|reboot|shutdown|poweroff|systemctl|pacman|yay|paru|apt|apt-get|dnf|zypper|flatpak|snap|curl|wget|ssh|scp|rsync|docker|podman|kubectl|helm|terraform|ansible|gpg|pass|secret-tool)\b/.test(lower)) return true;
        if (/(^|\s)git\s+(reset|checkout|clean|restore|rebase|merge|push|commit|am|apply|stash|branch|tag)\b/.test(lower)) return true;
        if (/(^|\s)(sqlite3|psql|mysql|mongosh)\b/.test(lower)) return true;
        if (/(^|\s)(-rf|-fr|--force|--delete)\b/.test(lower)) return true;
        return false;
    }

    function appendCommandRequest(message: AiMessageData, command: string) {
        const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${command}\n\`\`\``;
        message.rawContent += contentToAppend;
        message.content += contentToAppend;
    }

    function runShellCommand(command: string) {
        const responseMessage = createFunctionOutputMessage("run_shell_command", "", false);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = command;
        commandExecutionProc.running = true;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        root.runShellCommand(message.functionCall.args.command);
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            requester.makeRequest(); // Continue
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (root.currentMode === "chat" && name !== "run_shell_command") {
            addFunctionOutputMessage(name, Translation.tr("Blocked by Chat mode. Switch to `/mode Agent` to use this tool."));
            requester.makeRequest();
            return;
        }

        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            root.appendCommandRequest(message, args.command);
            if (root.currentMode === "chat") {
                if (!root.isAllowedChatReadCommand(args.command)) {
                    addFunctionOutputMessage(name, Translation.tr("Blocked by Chat mode. Only read-only file exploration commands are allowed: `cat`, `ls`, `dir`, `grep`, and `rg`."));
                    requester.makeRequest();
                    return;
                }
                root.runShellCommand(args.command);
                return;
            }
            if (root.isDangerousShellCommand(args.command)) {
                message.functionPending = true; // Wait for explicit user approval.
                return;
            }
            root.runShellCommand(args.command);
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
