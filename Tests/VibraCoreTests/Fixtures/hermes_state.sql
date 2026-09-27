-- Synthetic Hermes state.db: DDL shaped like the schema observed on
-- 2026-09-26 (schema_version 17), trimmed to the columns that matter plus a
-- few that must be ignored. Every id, path and message here is invented.
-- Times are seconds since 1970; base 1790000000.
CREATE TABLE sessions (
    id TEXT PRIMARY KEY, source TEXT NOT NULL, user_id TEXT, model TEXT,
    system_prompt TEXT, parent_session_id TEXT, started_at REAL NOT NULL,
    ended_at REAL, end_reason TEXT, message_count INTEGER DEFAULT 0,
    input_tokens INTEGER DEFAULT 0, output_tokens INTEGER DEFAULT 0,
    cache_read_tokens INTEGER DEFAULT 0, cache_write_tokens INTEGER DEFAULT 0,
    reasoning_tokens INTEGER DEFAULT 0, cwd TEXT, git_branch TEXT,
    estimated_cost_usd REAL, title TEXT, archived INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL REFERENCES sessions(id),
    role TEXT NOT NULL, content TEXT, tool_call_id TEXT, tool_calls TEXT, tool_name TEXT,
    timestamp REAL NOT NULL, token_count INTEGER, finish_reason TEXT, reasoning TEXT,
    active INTEGER, compacted INTEGER
);
CREATE INDEX idx_messages_session ON messages(session_id, timestamp);

INSERT INTO sessions (id, source, model, started_at, ended_at, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens, cwd, git_branch, title, archived, system_prompt) VALUES
 ('h_turn',     'cli',      'demo-model', 1790000000, NULL,       100, 20, 5, 1, 999, '/Users/demo/proj-a', 'main', 'turn', 0, 'SYSTEM PROMPT'),
 ('h_tool',     'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-b', NULL, NULL, 0, NULL),
 ('h_toolres',  'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-c', NULL, NULL, 0, NULL),
 ('h_user',     'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-d', NULL, NULL, 0, NULL),
 ('h_length',   'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-e', NULL, NULL, 0, NULL),
 ('h_rewound',  'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-f', NULL, NULL, 0, NULL),
 ('h_meta',     'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-g', NULL, NULL, 0, NULL),
 ('h_nomsg',    'cli',      'demo-model', 1790000050, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-h', NULL, NULL, 0, NULL),
 ('h_ended',    'cli',      'demo-model', 1790000000, 1790000900, 0, 0, 0, 0, 0, '/Users/demo/proj-i', NULL, NULL, 0, NULL),
 ('h_archived', 'cli',      'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '/Users/demo/proj-j', NULL, NULL, 1, NULL),
 ('h_sub',      'subagent', 'demo-model', 1790000000, 1790000500, 0, 0, 0, 0, 0, '/Users/demo/proj-k', NULL, NULL, 0, NULL),
 ('h_gateway',  'feishu',   'demo-model', 1790000000, NULL,       0, 0, 0, 0, 0, '',                    NULL, NULL, 0, NULL);

INSERT INTO messages (session_id, role, content, tool_calls, timestamp, finish_reason, active) VALUES
 ('h_turn',    'user',         'first question in proj-a', NULL, 1790000010, NULL,         1),
 ('h_turn',    'assistant',    'an answer',                NULL, 1790000020, 'stop',       1),
 ('h_tool',    'user',         'run the tests',            NULL, 1790000010, NULL,         1),
 ('h_tool',    'assistant',    NULL,                       '[]', 1790000030, 'tool_calls', 1),
 ('h_toolres', 'assistant',    NULL,                       '[]', 1790000010, 'tool_calls', 1),
 ('h_toolres', 'tool',         'tool output',              NULL, 1790000040, NULL,         1),
 ('h_user',    'assistant',    'done',                     NULL, 1790000010, 'stop',       1),
 ('h_user',    'user',         'and another thing',        NULL, 1790000050, NULL,         1),
 ('h_length',  'assistant',    'truncated',                NULL, 1790000060, 'length',     1),
 ('h_rewound', 'assistant',    'kept',                     NULL, 1790000070, 'stop',       1),
 ('h_rewound', 'user',         'rewound away',             NULL, 1790000080, NULL,         0),
 ('h_meta',    'assistant',    'fine',                     NULL, 1790000090, 'stop',       1),
 ('h_meta',    'session_meta', '{}',                       NULL, 1790000095, NULL,         1),
 ('h_ended',   'user',         'question in ended session', NULL, 1790000100, NULL,        1),
 ('h_archived','user',         'archived question',        NULL, 1790000100, NULL,         1),
 ('h_sub',     'user',         'subagent instruction',     NULL, 1790000100, NULL,         1),
 ('h_gateway', 'user',         'chat from the gateway',    NULL, 1790000100, NULL,         1),
 ('h_gateway', 'assistant',    'reply',                    NULL, 1790000110, 'stop',       1);
