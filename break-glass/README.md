# 🧯 break-glass — emergency demo fallback

**In case of demo emergency, break glass.**

These four files are a **known-good, pre-generated** OCM add-on bundle for the
node-exporter example — the exact output the skill *should* produce. They exist
so a live talk never dies on a bad skill run.

- `make demo` writes the skill's *live* output to `./ocm-addon-output/` — **not** here.
  This directory is never overwritten by the demo.
- If the live run misbehaves on stage, apply these instead:

  ```bash
  kubectl apply -f ./break-glass/
  kubectl get managedclusteraddon -A -w
  ```

Keep these in sync when the skill's output format changes (regenerate via
`make demo`, eyeball the diff, copy the good files back over these).
