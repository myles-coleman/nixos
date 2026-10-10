import { Plugin, usePlugin } from "@opencode/plugin/tui"
import { createMemo, Show } from "solid-js"

/**
 * Status bar contribution for the TUI footer.
 *
 * Shows a compact, reactive row with the git branch, selected model, and the
 * active session cost, appended to OpenCode's built-in health indicators.
 *
 * Configure via the object form in ~/.config/opencode/cli.json:
 *
 *   {
 *     "plugins": [
 *       { "package": "bee.status", "options": {
 *         "branch": true,
 *         "model": true,
 *         "cost": true,
 *         "version": false,
 *         "separator": "  ·  "
 *       } }
 *     ]
 *   }
 */

type StatusOptions = {
  branch?: boolean
  model?: boolean
  cost?: boolean
  version?: boolean
  separator?: string
}

function readOptions(raw: unknown): Required<StatusOptions> {
  const value = (raw ?? {}) as StatusOptions
  return {
    branch: value.branch !== false,
    model: value.model !== false,
    cost: value.cost !== false,
    version: value.version === true,
    separator: typeof value.separator === "string" ? value.separator : "  ·  ",
  }
}

function formatCost(value: number): string {
  return `$${value.toFixed(value > 0 && value < 0.01 ? 4 : 2)}`
}

function Status(props: { sessionID?: string }) {
  const context = usePlugin()
  const options = createMemo(() => readOptions(context.options))

  const location = context.location ?? context.data.location.default()

  const branch = createMemo(() => {
    if (!options().branch) return undefined
    try {
      const vcs = context.data.location.vcs.info(location)
      return vcs?.branch?.current ?? undefined
    } catch {
      return undefined
    }
  })

  const model = createMemo(() => {
    if (!options().model) return undefined
    try {
      const current = context.ui.model.current() as
        | { name?: string; id?: string }
        | undefined
      return current?.name ?? current?.id ?? undefined
    } catch {
      return undefined
    }
  })

  const cost = createMemo(() => {
    if (!options().cost || !props.sessionID) return undefined
    try {
      const value = context.data.session.cost(props.sessionID)
      if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
        return undefined
      }
      return formatCost(value)
    } catch {
      return undefined
    }
  })

  const version = createMemo(() =>
    options().version ? context.app.version : undefined,
  )

  const parts = createMemo(() =>
    [branch(), model(), cost(), version()].filter(
      (part): part is string => Boolean(part),
    ),
  )

  return (
    <Show when={parts().length > 0}>
      <text fg={context.theme.text.base}>
        {` ${parts().join(options().separator)} `}
      </text>
    </Show>
  )
}

export default Plugin.define({
  id: "bee.status",
  setup(context) {
    const location = context.location ?? context.data.location.default()

    // Keep VCS info available for the status row. Failure is non-fatal.
    void Promise.resolve(context.data.location.vcs.sync(location)).catch(
      () => {},
    )

    const disposers = [
      context.ui.slot({
        append: "prompt.footer.status",
        render: (input) => <Status sessionID={input?.sessionID} />,
      }),
      context.ui.slot({
        append: "home.footer.status",
        render: () => <Status />,
      }),
    ]

    return () => {
      for (const dispose of disposers) {
        if (typeof dispose === "function") dispose()
      }
    }
  },
})
