This markdown contains up to 5 most recently updated documents from the multi-document connection, followed by the API documentation for interacting with them.

# Document Content (for reference only, use the API below for up-to-date data)

## Verse

```json
[
  {
    "id": "028D1443-D49E-4B71-BE8E-3C626201C1E9",
    "type": "page",
    "textStyle": "page",
    "markdown": "Verse",
    "content": [
      {
        "id": "71EFBE72-B3F9-45B7-A499-E7C1B460B214",
        "type": "text",
        "markdown": ""
      }
    ]
  }
]
```

# Documentation of the Craft Multi-Document API

## Craft – Multi-Document API for Verse App

**Version:** 1.0.0

### Overview
The Craft Multi-Document API provides programmatic access to multiple Craft documents. Access documents, blocks, collections, and search across your document set with unified authentication.

### Key Concepts

**Document IDs**: Each document is identified by an ID. Use `GET /documents` to discover available documents and their IDs.

**Cross-Document Operations**: Most operations require specifying which document to work with via block IDs. The API automatically resolves which document a block belongs to.

### Recommended Usage
This API is ideal for building integrations that need to work with multiple related documents, such as project documentation sets, knowledge bases, or multi-document workflows.

### Development Tips
- Start with `GET /documents` to discover available documents and their IDs
- Use the `id` parameter in `GET /blocks` with a document's ID to fetch that document's content
- When inserting blocks, use `pageId` in the position object to specify the target document/block
- Use `GET /documents/search` to search across all documents with relevance-based ranking
- Collections can span multiple documents - use `GET /collections` to discover them

### Note for AI
When implementing functionality using this API, always make actual calls to these endpoints and verify the responses. Do not simulate or mock the API interactions or use hard-coded values on the client-side - use the real endpoints to ensure proper functionality and data handling.

**IMPORTANT: This is a production server connected to real user data.** Only perform testing operations that can be safely rolled back:

- Safe: Reading data (`GET` requests), creating test content that you delete immediately after
- Safe: Modifying content if you can restore it to its original state
- Safe: Moving blocks if you can move them back to their original position
- Unsafe: Permanent deletions, modifications without backup, or any changes you cannot reverse

Always verify rollback operations work before considering a test complete.

### Servers

- https://connect.craft.do/links/3sqDW0Dct3c/api/v1
  API Server for Multi-Document Connection

---

## Endpoints

## List Documents

`GET /documents`

Retrieve all documents accessible through this multi-document connection. Returns document IDs, titles, and deletion status for each document.

### Responses

#### 200
List of documents with their metadata

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "id": "doc-123",
      "title": "Project Plan",
      "isDeleted": false
    },
    {
      "id": "doc-456",
      "title": "Meeting Notes",
      "isDeleted": false
    },
    {
      "id": "doc-789",
      "title": "[Deleted Document]",
      "isDeleted": true
    }
  ]
}
```

---

## Fetch Blocks

`GET /blocks`

Fetches content from documents in this multi-document connection. Use 'id' query parameter to specify which block to fetch.

Use `Accept` header `application/json` for structured data, `text/markdown` for rendered content.

**Content Rendering:** Text blocks contain markdown formatting and markdown formatted output may include structural tags like `<page></page>`, etc. When displaying content, consider rendering markdown as formatted text or cleaning up the syntax for plain text display.

**Scope Filtering:** Block links in markdown and collections, as well as relations are filtered to documents scope. Block links and date links are returned as `block://` and `date://` URLs.

**Tip:** Start by calling GET /documents to list available documents, then use their documentId values as the 'id' parameter to fetch each document's root content.

### Parameters

- **id** (required) (query): string
  The ID of the page block to fetch. Required for multi-document operations. Accepts IDs for documents, pages and blocks.
- **maxDepth** (query): number
  The maximum depth of blocks to fetch. Default is -1 (all descendants). With a depth of 0, only the specified block is fetched. With a depth of 1, only direct children are returned.
- **fetchMetadata** (query): boolean
  Whether to fetch metadata (comments, createdBy, lastModifiedBy, lastModifiedAt, createdAt) for the blocks. Default is false.

### Responses

#### 200
Fetched block with nested children

**Content-Type:** `application/json`

```json
{
  "id": "doc-123",
  "type": "page",
  "textStyle": "page",
  "markdown": "<page>Project Plan</page>",
  "content": [
    {
      "id": "1",
      "type": "text",
      "textStyle": "h1",
      "markdown": "# Overview"
    },
    {
      "id": "2",
      "type": "text",
      "markdown": "This is the project overview document."
    }
  ]
}
```

**Content-Type:** `text/markdown`

```markdown
<page>
<pageTitle>Project Plan</pageTitle>
<content>
    # Overview

    This is the project overview document.
</content>
</page>
```

---

## Insert Blocks

`POST /blocks`

Insert content into documents in this multi-document connection. Content can be provided as structured JSON blocks. Use position parameter to specify where to insert. Returns the inserted blocks with their assigned block IDs for later reference.

### Request Body

**Content-Type:** `application/json`


**Example: textBlock**

Insert text block into document

```json
{
  "blocks": [
    {
      "type": "text",
      "markdown": "## New Section\n\n- Point A\n- Point B"
    }
  ],
  "position": {
    "position": "end",
    "pageId": "doc-123"
  }
}
```


**Example: markdown**

Insert markdown content

```json
{
  "markdown": "## New Section\n\n- Point A\n- Point B",
  "position": {
    "position": "end",
    "pageId": "doc-123"
  }
}
```

### Responses

#### 200
Array of inserted blocks with assigned IDs

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "type": "text",
      "id": "string",
      "textStyle": "card",
      "textAlignment": "left",
      "font": "system",
      "cardLayout": "small",
      "markdown": "string",
      "indentationLevel": 0,
      "listStyle": "none",
      "decorations": [
        "callout"
      ],
      "color": "string",
      "taskInfo": {
        "state": "todo",
        "scheduleDate": "2024-01-01",
        "deadlineDate": "2024-01-01"
      },
      "metadata": {
        "lastModifiedAt": "2024-01-01",
        "createdAt": "2024-01-01",
        "lastModifiedBy": "string",
        "createdBy": "string",
        "comments": [
          {
            "id": "string",
            "author": "string",
            "content": "string",
            "createdAt": "2024-01-01"
          }
        ]
      }
    }
  ]
}
```

---

## Delete Blocks

`DELETE /blocks`

Delete content from documents in this multi-document connection. Removes specified blocks by their IDs.

### Request Body

**Content-Type:** `application/json`

```json
{
  "blockIds": [
    "7",
    "9",
    "12"
  ]
}
```

### Responses

#### 200
Array of deleted block IDs

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "id": "string"
    }
  ]
}
```

---

## Update Blocks

`PUT /blocks`

Update content across documents in this multi-document connection. For text blocks, provide updated markdown content. Only the fields that are provided will be updated.

### Request Body

**Content-Type:** `application/json`

```json
{
  "blocks": [
    {
      "id": "5",
      "markdown": "## Updated Section\n\nUpdated content"
    }
  ]
}
```

### Responses

#### 200
Array of updated blocks

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "type": "text",
      "id": "string",
      "textStyle": "card",
      "textAlignment": "left",
      "font": "system",
      "cardLayout": "small",
      "markdown": "string",
      "indentationLevel": 0,
      "listStyle": "none",
      "decorations": [
        "callout"
      ],
      "color": "string",
      "taskInfo": {
        "state": "todo",
        "scheduleDate": "2024-01-01",
        "deadlineDate": "2024-01-01"
      },
      "metadata": {
        "lastModifiedAt": "2024-01-01",
        "createdAt": "2024-01-01",
        "lastModifiedBy": "string",
        "createdBy": "string",
        "comments": [
          {
            "id": "string",
            "author": "string",
            "content": "string",
            "createdAt": "2024-01-01"
          }
        ]
      }
    }
  ]
}
```

---

## Move Blocks

`PUT /blocks/move`

Move blocks to reorder them or move them between documents. Returns the moved block IDs.

### Request Body

**Content-Type:** `application/json`

```json
{
  "blockIds": [
    "9",
    "10"
  ],
  "position": {
    "position": "end",
    "pageId": "doc-456"
  }
}
```

### Responses

#### 200
Array of moved block IDs

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "id": "string"
    }
  ]
}
```

---

## Search in Document

`GET /blocks/search`

Search content in one single Craft document. This is a secondary search tool that complements documents_search by allowing you to search within a single document.

### Parameters

- **documentId** (required) (query): string
  The document ID to search within.
- **pattern** (required) (query): string
  The search patterns to look for. Supports NodeJS regular expressions.
- **caseSensitive** (query): boolean
  Whether the search should be case sensitive. Default is false.
- **beforeBlockCount** (query): number
  The number of blocks to include before the matched block.
- **afterBlockCount** (query): number
  The number of blocks to include after the matched block.

### Responses

#### 200
Array of search matches with structured context

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "blockId": "5",
      "markdown": "Project planning meeting notes",
      "pageBlockPath": [
        {
          "id": "doc-123",
          "content": "Project Plan"
        }
      ],
      "beforeBlocks": [
        {
          "blockId": "4",
          "markdown": "# Overview"
        }
      ],
      "afterBlocks": [
        {
          "blockId": "6",
          "markdown": "Next steps for the project"
        }
      ]
    }
  ]
}
```

---

## Search across Documents

`GET /documents/search`

Search content across multiple documents using relevance-based ranking. This endpoint uses FlexiSpaceSearch to find matches across the documents in your multi-document connection.

- Search across all documents or filter to specific documents
- Optional document filtering (include or exclude specific documents)
- Relevance-based ranking (top 20 results)
- Content snippets with match highlighting
- Returns exposedDocumentId for each result

**Example Use Cases:**
- Find all mentions of a topic across project documents
- Search for specific content excluding certain documents
- Locate references across a set of related documents

### Parameters

- **include** (required) (query): string
  Search terms to include in the search. Can be a single string or array of strings.
- **documentIds** (query): string
  The document IDs to filter. If not provided, all documents will be searched. Can be a single string or array of strings.
- **documentFilterMode** (query): string
  Whether to include or exclude the specified documents. Default is 'include'. Only used when documentIds is provided.

### Responses

#### 200
Array of search matches across documents with match highlighting

**Content-Type:** `application/json`


**Example: basicSearch**

Search for 'API' across all documents

```json
{
  "items": [
    {
      "documentId": "doc-123",
      "markdown": "The **API** endpoints are documented..."
    },
    {
      "documentId": "doc-456",
      "markdown": "**API** authentication requires..."
    }
  ]
}
```

**Example: filteredSearch**

Search with document filtering

```json
{
  "items": [
    {
      "documentId": "doc-123",
      "markdown": "Authentication **token** is required..."
    }
  ]
}
```

---

## List Collections

`GET /collections`

List all collections across documents in this multi-document connection

### Parameters

- **documentIds** (query): array
  The document IDs to filter. If not provided, collections in all documents will be listed.
- **documentFilterMode** (query): string
  Whether to include or exclude the specified documents. Default is 'include'. Only used when documentIds is provided.

### Responses

#### 200
List of collections with metadata

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "key": "col-123",
      "name": "Tasks",
      "documentId": "doc-123",
      "schema": {
        "name": "Tasks",
        "properties": []
      }
    },
    {
      "key": "col-456",
      "name": "Team Members",
      "documentId": "doc-456",
      "schema": {
        "name": "Team Members",
        "properties": []
      }
    }
  ]
}
```

---

## Get Collection Schema

`GET /collections/{collectionId}/schema`

Get the schema for a collection by its ID.

**Format Options** (via `format` query parameter):
- `json-schema-items` (default): Returns JSON Schema for validating collection items (use with add/update endpoints)
- `schema`: Returns the collection's schema structure (name, properties, types)

Use the collection ID from the `/collections` endpoint.

### Parameters

- **format** (query): string
  The format to return the schema in. Default: json-schema-items. - 'schema': Returns the collection schema structure that can be edited - 'json-schema-items': Returns JSON Schema for addCollectionItems/updateCollectionItems validation
- **collectionId** (required) (path): string
  The unique ID of the collection (obtained from /collections endpoint)

### Responses

#### 200
Collection schema in requested format

**Content-Type:** `application/json`


**Example: jsonSchemaFormat**

JSON Schema format (format=json-schema-items, default)

```json
{
  "type": "object",
  "properties": {
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "title": {
            "type": "string"
          },
          "properties": {
            "type": "object"
          }
        },
        "required": [
          "title"
        ]
      }
    }
  },
  "required": [
    "items"
  ]
}
```

**Example: schemaFormat**

Schema structure format (format=schema)

```json
{
  "name": "Project Tasks",
  "properties": [
    {
      "name": "Status",
      "type": "singleSelect",
      "options": [
        {
          "name": "To Do"
        },
        {
          "name": "In Progress"
        },
        {
          "name": "Done"
        }
      ]
    },
    {
      "name": "Due Date",
      "type": "date"
    }
  ]
}
```

---

## Get Collection Items

`GET /collections/{collectionId}/items`

Retrieve all items from a specific collection. Use the collection ID from the `/collections` endpoint.

### Parameters

- **maxDepth** (query): number
  The maximum depth of nested content to fetch for each collection item. Default is -1 (all descendants). With a depth of 0, only the item properties are fetched without nested content.
- **collectionId** (required) (path): string
  The unique ID of the collection (obtained from /collections endpoint)

### Responses

#### 200
Collection items retrieved successfully

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "title": "Title 1",
      "properties": {}
    }
  ]
}
```

---

## Add Collection Items

`POST /collections/{collectionId}/items`

Add new items to a specific collection.

### Parameters

- **collectionId** (required) (path): string
  The unique ID of the collection

### Request Body

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "title": "string",
      "properties": {}
    }
  ]
}
```

### Responses

#### 200
Items added successfully

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "title": "Title 1",
      "properties": {}
    }
  ]
}
```

---

## Delete Collection Items

`DELETE /collections/{collectionId}/items`

Delete items from a specific collection by their IDs.

### Parameters

- **collectionId** (required) (path): string
  The unique ID of the collection

### Request Body

**Content-Type:** `application/json`

```json
{
  "idsToDelete": [
    "1",
    "2"
  ]
}
```

### Responses

#### 200
Items deleted successfully

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "id": "string"
    }
  ]
}
```

---

## Update Collection Items

`PUT /collections/{collectionId}/items`

Update existing items in a specific collection.

### Parameters

- **collectionId** (required) (path): string
  The unique ID of the collection

### Request Body

**Content-Type:** `application/json`

```json
{
  "itemsToUpdate": [
    {
      "id": "string",
      "title": "string",
      "properties": {}
    }
  ]
}
```

### Responses

#### 200
Items updated successfully

**Content-Type:** `application/json`

```json
{
  "items": [
    {
      "title": "Title 1",
      "properties": {}
    }
  ]
}
```

---
