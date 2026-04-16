# ask_self

`ask_self` is a portable repository-grounded RAG scaffold for codebase Q&A. It builds a local sqlite-vec index from a repo corpus, retrieves relevant chunks with Gemini embeddings, and asks Gemini Pro to synthesize a final answer with optional question-quality feedback.

This README is written for the next LLM or engineer who inherits this folder and wants to maintain or spin it out into its own repository.

**Purpose**
This package exists to answer questions about a repository using the repository itself as the source of truth.

- It ingests docs, source files, and optional GitHub PR history into a local vector index.
- It retrieves semantically relevant chunks for a user question.
- It synthesizes a final answer from retrieved context instead of answering from model memory alone.
- It can assess whether the original question is vague, broad, or underspecified, and suggest a better question.

**Core Files**
- `ask_self_ingest.py`: builds the local sqlite-vec index from the configured corpus.
- `ask_self_query.py`: embeds a query, performs KNN retrieval, then calls Gemini Pro for structured synthesis.
- `ask_self_harness.py`: repo-specific configuration loader, env-file loader, and path helpers.
- `ask_self_harness.json`: repo-specific policy for corpus selection, labels, env file location, DB naming, and GitHub settings.
- `ask_self_system_instructions.json`: user-editable synthesis instruction layers for Gemini Pro.
- `ask_self_helpers.py`: chunking and context-format helpers.

**Runtime Architecture**
1. `ask_self_ingest.py` loads the harness config.
2. The harness loads a `.env`-style file from `temp/ask-self-rag.env` by default if it exists.
3. Ingest walks the repo using harness include and exclude rules.
4. Each file is classified into a source type and chunking strategy.
5. Chunks are embedded with `gemini-embedding-001`.
6. Embeddings plus metadata are written into sqlite plus sqlite-vec.
7. `ask_self_query.py` embeds the user question with `gemini-embedding-001`.
8. Query retrieves nearest chunks from sqlite-vec and reranks slightly by source priority.
9. Query loads layered system instructions from `ask_self_system_instructions.json`.
10. Gemini Pro synthesizes a structured answer from retrieved context.
11. The renderer formats the answer, caveats, question assessment, better-question suggestion, and source list.

**Model Split**
- Retrieval embeddings: `gemini-embedding-001`
- Final synthesis: `gemini-pro-latest`

The system is classic RAG. Retrieval and synthesis are intentionally separate so you can swap either layer independently later.

**Configuration Model**
The main extension point is `ask_self_harness.json`.

The harness controls:
- `repo_label`: label injected into synthesis prompts.
- `db_filename` or `db_path`: where the sqlite index lives.
- `system_instructions_path`: which user-editable instruction file drives final synthesis.
- `env_file_path`: where runtime credentials are loaded from. Default is `temp/ask-self-rag.env`.
- `github`: optional PR-ingestion settings.
- `docs` and `source`: include patterns, exclude patterns, and file extensions.
- `classification_rules`: how files map to `doc`, `script`, `pattern`, `test`, `changelog`, or other source classes.

If you spin this into its own repo, preserve the distinction between:
- generic engine behavior in Python code
- repo policy in `ask_self_harness.json`
- answer behavior in `ask_self_system_instructions.json`

That split is the main architectural boundary worth protecting.

**System Instruction Layer**
`ask_self_system_instructions.json` is intentionally user-editable.

It currently supports layered instructions:
- `base_system`
- `repo_context_system`
- `answer_style_system`
- `question_quality_system`
- `query_improvement_system`

It also defines a response contract for structured synthesis output. Keep this file editable and outside the code path for normal prompt tuning. If maintainers need to change answer behavior, they should start there rather than editing Python code.

**Credential Handling**
This package is intentionally biased toward keeping credentials out of tracked files.

- Default runtime env file: `temp/ask-self-rag.env`
- The harness auto-loads that file if present.
- Existing shell environment variables override file values.
- `temp/` should remain gitignored in any spun-out repo.

Expected env vars:
- `GOOGLE_API_KEY`
- `GITHUB_TOKEN` or another token name referenced by `github.token_env_vars`
- optional tenancy env var such as `WP_CODE_CHECK_SELF_ASK_TEAM_ID`

Example `temp/ask-self-rag.env`:

```env
GOOGLE_API_KEY=your-gemini-key
GITHUB_TOKEN=your-github-pat
WP_CODE_CHECK_SELF_ASK_TEAM_ID=optional-team-id
```

Do not store real credentials in `ask_self_harness.json`, `README.md`, or any committed `.env` file.

**Current Query Output Contract**
`ask_self_query.py --json` returns structured fields that downstream tools can consume:

- `answer`
- `supporting_evidence`
- `caveats`
- `question_assessment`
- `better_question`
- `why_this_is_better`
- `sources_consulted`
- `rendered_answer`

`rendered_answer` is a convenience field for terminal UX. If you build an API or UI around this package, prefer the structured fields and treat `rendered_answer` as presentation only.

**Known Engineering Tradeoffs**
- Gemini sometimes ignores JSON-only instructions or truncates structured output. The query layer contains repair and fallback logic to recover usable fields.
- Retrieval quality depends heavily on harness corpus policy. Bad include patterns will hurt answer quality faster than prompt tuning will fix it.
- The reranking logic is deliberately light. It nudges by priority but does not attempt cross-encoder style reranking.
- `sqlite_vec` is a runtime dependency. The package lazy-loads it so `--help` still works when the native extension is not installed.
- PR ingestion is optional and network-dependent. It should remain non-critical to local repo Q&A.

**How To Extend It**
- To support a new repo: copy the folder, rewrite `ask_self_harness.json`, update `ask_self_system_instructions.json`, and rebuild the index.
- To support new source types: add a new classification rule plus a chunking strategy if needed.
- To change answer behavior: edit `ask_self_system_instructions.json`.
- To change retrieval behavior: edit chunking, classification, or KNN/reranking logic in Python.
- To change models: update the model constants in `ask_self_ingest.py` and `ask_self_query.py`.

**If You Spin This Out**
Recommended repo contents:
- `ask_self_ingest.py`
- `ask_self_query.py`
- `ask_self_harness.py`
- `ask_self_helpers.py`
- `README.md`
- example `ask_self_harness.json`
- example `ask_self_system_instructions.json`
- `.gitignore` with `temp/`, `.venv/`, and sqlite artifacts ignored

Recommended follow-up work after spinout:
- add automated tests for env loading, harness loading, chunking, and structured-answer recovery
- add a small CLI wrapper with named commands
- add a sample harness for Python, PHP, and docs-heavy repos
- add a machine-readable schema file for the harness JSON

**Maintainer Rule**
If behavior feels repo-specific, put it in the harness or system-instructions file.
If behavior feels universally true for this RAG engine, put it in Python.
