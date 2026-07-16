# Elchai Internal Document Q&A Assistant

A Retrieval-Augmented Generation (RAG) prototype built for Elchai Group's AI Agent & OpenClaw Research Internship pre-interview assessment. It lets employees ask natural-language questions about internal documents and receive answers grounded strictly in the company's own knowledge base — no answers from the model's general/public training knowledge.

Built with **n8n** for orchestration, **OpenAI** for embeddings and generation, **Supabase (pgvector)** for vector storage, and **Google Drive** as the document source.

---

## How it works

Two workflows make up the system:

### 1. Knowledge base ingestion (`workflows/kb-ingestion.workflow.json`)

Watches a designated Google Drive folder and indexes every document inside it.

```
Trigger (manual bulk load OR hourly Google Drive poll)
    → List files in Google Drive folder
    → Download file (PDF / DOCX / TXT)
    → Document Loader — extract raw text
    → Text Splitter — chunk into ~1,000 characters, 200-character overlap
    → OpenAI Embeddings (text-embedding-3-small) — 1,536-dimension vector per chunk
    → Supabase Vector Store INSERT — store chunk text + vector + metadata
```

### 2. Document Q&A chat (`workflows/kb-chat.workflow.json`)

Lets an employee ask a question and get a grounded answer back in real time.

```
Chat trigger — employee sends a message
    → AI Agent (GPT-4o) — loads last 10 turns of conversation history
    → Mandatory tool call: search_knowledge_base (agent must search before answering)
        → Embed the question (text-embedding-3-small)
        → Cosine similarity search against Supabase `documents` table
        → Retrieve top 5 most relevant chunks
    → GPT-4o synthesises an answer using only the retrieved chunks
    → Streamed response returned to the chat interface
```

**Human review status:** there is currently no human-in-the-loop approval gate — responses are delivered directly to the user. See [Known limitations](#known-limitations) and [Risks](#risks--safety-controls) below before using this on real company data.

---

## Repo structure

```
elchai-document-qa/
├── README.md
├── workflows/
│   ├── kb-ingestion.workflow.json   # n8n workflow — document ingestion (bulk + auto-sync)
│   └── kb-chat.workflow.json        # n8n workflow — conversational Q&A agent
└── supabase/
    └── setup.sql                    # Creates the documents table + pgvector match function
```

---

## Setup

### Prerequisites

- An [n8n](https://n8n.io) instance (self-hosted or cloud)
- A [Supabase](https://supabase.com) project with the `pgvector` extension enabled
- An OpenAI API key (for embeddings + GPT-4o)
- A Google Drive account with a designated folder for source documents, plus OAuth2 credentials set up in n8n

### 1. Set up Supabase

Run `supabase/setup.sql` in the Supabase SQL editor. This creates the `documents` table (`id`, `content`, `metadata`, `embedding`) and the `match_documents` function used for cosine similarity search.

### 2. Import the workflows into n8n

In n8n: **Workflows → Import from File**, and import both:
- `workflows/kb-ingestion.workflow.json`
- `workflows/kb-chat.workflow.json`

### 3. Connect credentials

In each imported workflow, reconnect the credential nodes to your own:
- OpenAI API key (embeddings + GPT-4o nodes)
- Supabase project URL + service key
- Google Drive OAuth2 connection, pointed at your source folder ID

### 4. Run ingestion

Trigger `kb-ingestion` manually once to bulk-index existing files, then activate it so the hourly Google Drive poll picks up new or updated files automatically.

### 5. Activate the chat workflow

Activate `kb-chat` and open its chat interface (or embed it) to start asking questions.

---

## Known limitations

| Limitation | Impact |
|---|---|
| `text-embedding-3-small` has an 8,191-token input limit per chunk | Long documents must be chunked — handled by the 1,000-character splitter |
| GPT-4o context window limits how many retrieved chunks can be used at once | Currently top 5 chunks retrieved — may miss relevant content in large knowledge bases |
| No OCR support | Scanned/image-only PDFs return empty text — only text-based PDFs work |
| Supabase free tier auto-pauses after 1 week of inactivity | Production use requires a paid Supabase plan or a periodic keep-alive |
| No confidence score surfaced to the user | Users can't tell whether a retrieved match was strong or weak |
| Conversation memory is session-scoped | Closing the chat resets history — no cross-session memory |
| No deduplication on re-ingestion | Re-running bulk load re-inserts the same document, creating duplicate chunks |
| No human review gate | Responses go straight to the user with no approval step (see below) |

## Risks & safety controls

Full risk breakdown, severity ratings, and mitigations are documented in the assessment report. In short: **hallucination** and **lack of human review** are the two highest-severity risks — both are mitigated in the system prompt (never answer from memory; say "not found" if nothing relevant is retrieved) but neither is structurally enforced. Before pointing this at real confidential or HR data, add a human review/escalation layer and per-user access control (see the full report for details).

## Status

**Prototype / test only.** Recommended next step: pilot on non-sensitive documents with a human review layer added before any production rollout.
