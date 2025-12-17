# Simple Bun Executable Example

This is a super simple Bun example that can be compiled into a standalone executable.

## Build the Executable

```bash
bun build index.js --compile --outfile bun-example
```

This will create a standalone executable named `bun-example` that includes the Bun runtime.

## Run the Executable

After building, you can run it directly:

```bash
./bun-example
```

Or copy it to a remote system and run it there (no Bun installation needed on the remote system).

## What it does

The script:
- Prints a success message
- Shows Node version, platform, and architecture
- Displays current time
- Validates that Bun runtime is available
- Creates an `issues.json` file with sample health check issues

