Integration ideas worth considering:

The scanner is grep-based and structural; ask_self is semantic. That's a complementary pairing, not a redundant one:

Finding explainer / triage assistant — Scanner flags 30 issues across a site. Feed those findings into ask_self as a query: "Why does this repo use $wpdb->prepare() this way?" or "Is this eval() usage intentional?" It can pull from PRs, changelogs, and docs to tell you whether a finding is a known pattern or a real concern. Cuts triage time.

False positive reducer — Scanner's grep can't see multi-line sanitization or architectural intent. ask_self can retrieve chunks showing that a flagged pattern is wrapped in a mitigation elsewhere. This is the "secondary evaluator" you're intuiting — a semantic second opinion on structural matches.

Pattern gap discovery — "What risks exist in this repo that the scanner doesn't check for?" is a question ask_self can actually attempt, since it has the pattern library and the source indexed together.

Remediation grounded in repo conventions — Instead of generic "use prepared statements" advice, ask_self can show how this specific repo already handles that pattern elsewhere.

AI-DDTK - POTENTIAL INTEGRATION
https://github.com/Hypercart-Dev-Tools/AI-DDTK-Fix-Iterate-Loop/

## Review System Instruction Layer (Sketch)

This layer would live alongside the existing Q&A layers in `ask_self_system_instructions.json`.
It is designed to be invoked by an AI agent inside a Fix-Iterate Loop (see AI-DDTK)
rather than by a human asking freeform questions.

### System instruction additions

```json
{
  "system_layers": {
    "...existing layers unchanged...": "...",

    "review_system": "You are a code reviewer with access to the full indexed codebase. You are given a diff or file excerpt. Your job is to identify violations of DRY, SOLID, and repo-specific conventions by comparing the submitted code against existing patterns in the retrieved context. Do not invent violations — only flag issues where the retrieved context provides concrete evidence of an existing pattern, utility, or abstraction that the new code duplicates or contradicts. If you find no violations, say so explicitly.",

    "review_severity_system": "Classify each violation as: MUST_FIX (blocks merge — duplication of existing utility, broken interface contract, security regression), SHOULD_FIX (strong suggestion — could use existing abstraction, naming inconsistency with established conventions), or CONSIDER (style preference — alternative exists but current approach is acceptable). Never inflate severity."
  }
}
```

### Review response contract

```json
{
  "review_response_contract": {
    "format": "json",
    "fields": {
      "verdict": "one of: clean, has_violations",
      "violations": [
        {
          "principle": "DRY | SRP | OCP | LSP | ISP | DIP | CONVENTION",
          "severity": "MUST_FIX | SHOULD_FIX | CONSIDER",
          "location": "file path and line range in the submitted diff",
          "description": "what the violation is",
          "existing_pattern": "file path and excerpt from the indexed codebase that the new code duplicates or contradicts",
          "suggested_fix": "concrete refactoring suggestion grounded in the existing pattern"
        }
      ],
      "summary": "one-sentence overall assessment",
      "sources_consulted": ["array of retrieved chunk sources"]
    }
  }
}
```

### How this fits the AI-DDTK Fix-Iterate Loop

The review layer slots into Step 3 (Verify) of the Fix-Iterate Loop.
The AI agent is the loop controller; ask_self is the verification oracle.

```
Fix-Iterate Loop (AI-DDTK)          ask_self (WPCC)
─────────────────────────           ───────────────
1. Agent writes/modifies code
                                    
2. Agent extracts diff:
   git diff --cached > /tmp/diff
                                    
3. Verify via ask_self:             ◄── ask_self_review.py --diff /tmp/diff
                                        --checks dry,srp,convention
                                        --harness-config ask_self_harness.json
                                        --json
                                    
                                    Returns structured verdict:
                                    {
                                      "verdict": "has_violations",
                                      "violations": [
                                        {
                                          "principle": "DRY",
                                          "severity": "MUST_FIX",
                                          "location": "src/utils/parse.py:42-58",
                                          "existing_pattern": "src/lib/parser.py:10-25 — parse_input() already does this",
                                          "suggested_fix": "Import and call parse_input() from src/lib/parser.py"
                                        }
                                      ]
                                    }
                                    
4. Agent reads verdict:
   - "clean" → done, exit loop
   - "has_violations" → apply
     suggested_fix, loop to step 1
                                    
5. Guardrails (from AI-DDTK):
   - 5 failed iterations → stop
   - 10 total iterations → stop
   - Confidence trending down → stop
```

### Iteration template (extends AI-DDTK format)

```
ITERATION N:
1. What I changed: [describe code change]
2. Diff: [file paths and line counts]
3. ask_self command: ask_self_review.py --diff /tmp/diff --checks dry,srp --json
4. Expected result: {"verdict": "clean"}
5. Actual result: [paste structured verdict]
6. Status: CLEAN / N violations (X MUST_FIX, Y SHOULD_FIX, Z CONSIDER)
7. Next action: [apply suggested fixes or stop]

META-REFLECTION (Iteration N):
Confidence: [1-10]
Violations trending: [up/down/flat]
Risk: [LOW / MEDIUM / HIGH]
Continue? [YES / NO / ASK_HUMAN]
```

### MCP tool definition (for VS Code agent integration)

For Claude Code or other VS Code agents to call ask_self natively in the loop,
expose it as an MCP tool. Minimal definition:

```json
{
  "tools": [
    {
      "name": "ask_self_review",
      "description": "Review a code diff against the indexed codebase for DRY, SOLID, and convention violations. Returns structured violations with evidence from existing code.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "diff": {
            "type": "string",
            "description": "Unified diff text to review"
          },
          "checks": {
            "type": "array",
            "items": {"type": "string", "enum": ["dry", "srp", "ocp", "lsp", "isp", "dip", "convention"]},
            "description": "Which principles to check. Defaults to all."
          },
          "harness_config": {
            "type": "string",
            "description": "Path to ask_self_harness.json"
          }
        },
        "required": ["diff"]
      }
    },
    {
      "name": "ask_self_query",
      "description": "Ask a natural-language question about the indexed codebase. Returns a grounded answer with sources.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "question": {
            "type": "string",
            "description": "The question to ask"
          },
          "harness_config": {
            "type": "string",
            "description": "Path to ask_self_harness.json"
          }
        },
        "required": ["question"]
      }
    }
  ]
}
```

The MCP server would be a thin wrapper: parse input → call ask_self CLI → return JSON.
The `--json` output contract already exists — no new serialization needed.

### What lives where

| Concern | Home | Why |
|---------|------|-----|
| Loop control, guardrails, iteration template | AI-DDTK | Generic agent pattern, not ask_self-specific |
| Review system instructions, severity rules | ask_self_system_instructions.json | Answer-behavior config, not code |
| Diff parsing, review-mode query construction | ask_self_review.py (new) | Engine code, repo-agnostic |
| MCP server adapter | AI-DDTK or standalone | Integration glue, should live near the agent |
| Repo-specific convention rules | ask_self_harness.json per repo | Policy, not code |

### Implementation order (suggested)

1. Add `review_system` and `review_severity_system` layers to ask_self_system_instructions.json
2. Add `review_response_contract` to the same file
3. Write `ask_self_review.py` — accepts a diff, embeds it, queries with review instructions, returns structured verdict
4. Test manually: `git diff HEAD~1 | python3 ask_self_review.py --json`
5. Wrap as MCP tool in AI-DDTK
6. Wire into Fix-Iterate Loop template as the verify step