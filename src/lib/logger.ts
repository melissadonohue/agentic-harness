/**
 * Structured JSON logger — cross-cutting seam.
 *
 * Outputs one JSON object per log call to stdout via console methods.
 * Works on both server (Node) and client (browser) without external deps.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Logger {
  info(message: string, context?: Record<string, unknown>): void;
  warn(message: string, context?: Record<string, unknown>): void;
  error(
    message: string,
    errorOrContext?: Error | Record<string, unknown>,
    context?: Record<string, unknown>,
  ): void;
  debug(message: string, context?: Record<string, unknown>): void;
  child(context: Record<string, unknown>): Logger;
}

type LogLevel = 'info' | 'warn' | 'error' | 'debug';

interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: string;
  context?: Record<string, unknown>;
  error?: { name: string; message: string; stack?: string };
}

// ---------------------------------------------------------------------------
// Serialisation helpers
// ---------------------------------------------------------------------------

function serializeError(err: Error): LogEntry['error'] {
  return {
    name: err.name,
    message: err.message,
    stack: err.stack,
  };
}

function isError(value: unknown): value is Error {
  return value instanceof Error;
}

// ---------------------------------------------------------------------------
// Console writers keyed by level
// ---------------------------------------------------------------------------

const writers: Record<LogLevel, (json: string) => void> = {
  info: (json) => console.info(json),
  warn: (json) => console.warn(json),
  error: (json) => console.error(json),
  debug: (json) => console.debug(json),
};

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export function createLogger(baseContext?: Record<string, unknown>): Logger {
  const base: Record<string, unknown> = baseContext ?? {};

  function emit(level: LogLevel, entry: Omit<LogEntry, 'level' | 'timestamp'>): void {
    if (level === 'debug' && process.env.NODE_ENV === 'production') {
      return;
    }

    const merged: Record<string, unknown> | undefined =
      Object.keys(base).length === 0 && entry.context === undefined
        ? undefined
        : { ...base, ...entry.context };

    const record: LogEntry = {
      level,
      message: entry.message,
      timestamp: new Date().toISOString(),
      ...(merged !== undefined && { context: merged }),
      ...(entry.error !== undefined && { error: entry.error }),
    };

    writers[level](JSON.stringify(record));
  }

  return {
    info(message, context) {
      emit('info', { message, context });
    },

    warn(message, context) {
      emit('warn', { message, context });
    },

    error(message, errorOrContext?, context?) {
      if (isError(errorOrContext)) {
        emit('error', {
          message,
          error: serializeError(errorOrContext),
          context,
        });
      } else {
        emit('error', {
          message,
          context: errorOrContext ?? context,
        });
      }
    },

    debug(message, context) {
      emit('debug', { message, context });
    },

    child(childContext) {
      return createLogger({ ...base, ...childContext });
    },
  };
}

// ---------------------------------------------------------------------------
// Default instance
// ---------------------------------------------------------------------------

export const logger: Logger = createLogger();
