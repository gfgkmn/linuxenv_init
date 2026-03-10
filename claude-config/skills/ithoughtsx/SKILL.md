# iThoughtsX Skill

Work with the currently open iThoughtsX mind map.

## Commands

```bash
# Basic commands
ithoughts-tool create <filepath> [root_text] # Create new empty mind map
ithoughts-tool read                         # Get map as JSON
ithoughts-tool write                        # Write full JSON from stdin
ithoughts-tool path                         # Get current file path

# Partial update commands
ithoughts-tool get <uuid>                   # Get a specific node by UUID
ithoughts-tool find <pattern>               # Find nodes by text (regex)
ithoughts-tool update <uuid> <json>         # Update node properties (merge)
ithoughts-tool add <parent_uuid> <json>     # Add child node(s) to parent
ithoughts-tool delete <uuid>                # Delete a node by UUID
ithoughts-tool set <uuid> <field> <value>   # Set a single field value

# LaTeX rendering commands
ithoughts-tool latex                        # Batch render all unrendered $$...$$ nodes
ithoughts-tool latex --all                  # Force re-render ALL $$...$$ nodes
ithoughts-tool latex --server URL           # Use custom LaTeX server
ithoughts-tool latex-server                 # Start local LaTeX rendering server
ithoughts-tool latex-server --port 9999     # Start on custom port
```

## JSON Format

```json
{
  "text": "Node title",
  "uuid": "preserve-this",
  "note": "optional notes",
  "children": [...]
}
```

## Usage Examples

### Create a new mind map
```bash
ithoughts-tool create /path/to/new.itmz              # Default root: "Central Topic"
ithoughts-tool create /path/to/new.itmz "My Project"  # Custom root text
```

### Find a node by text pattern
```bash
ithoughts-tool find "Qwen"
# Returns: [{"uuid": "xxx", "text": "Qwen 2.5 7B", "note": ""}]
```

### Get a specific node
```bash
ithoughts-tool get "0B8F2FC2-A729-4046-9D25-0D7D1CB4B6BE"
```

### Add children to a node
```bash
ithoughts-tool add "PARENT-UUID" '{"text": "New child node"}'
ithoughts-tool add "PARENT-UUID" '[{"text": "Child 1"}, {"text": "Child 2"}]'
```

### Update a node's text
```bash
ithoughts-tool set "NODE-UUID" text "New text content"
```

### Update multiple properties
```bash
ithoughts-tool update "NODE-UUID" '{"text": "New title", "note": "New note"}'
```

### Delete a node
```bash
ithoughts-tool delete "NODE-UUID"
```

## LaTeX Rendering

Nodes containing `$$...$$` delimiters are rendered as math images.

### Start the server (needed once)
```bash
ithoughts-tool latex-server                 # Runs on localhost:18088
# Or run in background:
nohup ithoughts-tool latex-server &
```

### Batch render all LaTeX nodes
```bash
ithoughts-tool latex                        # Render unrendered nodes only
ithoughts-tool latex --all                  # Force re-render everything
```

### How it works
- Extracts math from `$$...$$` delimiters in node text
- Sends to local server (pdflatex + pdftocairo + ImageMagick trim)
- Injects rendered PNGs directly into the .itmz file as assets
- iThoughtsX picks up images on file reload

### iThoughtsX live rendering (optional)
Set this in iThoughtsX Preferences → Server field for manual double-click rendering:
```
http://localhost:18088/latex?tex=%TEX%&scale=%SCALE%
```

## Workflow

1. Use `find` to locate nodes by text pattern
2. Use `get` to inspect a specific node
3. Use `add`, `update`, `set`, or `delete` for partial modifications
4. Use `latex` to batch render all LaTeX math nodes
5. UUIDs are auto-generated for new nodes if not provided
