// A compact badge under the 03 bindings list. Renders the localized line with
// the literal "Logitech" turned into a brand-colour (teal) tag, splitting on the
// word so it adapts to each language's word order.
export function LogiKeymap({ label }: { label: string }) {
  return (
    <div className="mt-6 inline-flex items-center rounded-full border border-white/10 bg-[#000000c9] px-4 py-2">
      <span className="font-mono text-[11px] tracking-wide text-white/60">
        {label.split("Logitech").map((part, i) => (
          <span key={i}>
            {i > 0 && (
              <span
                className="mx-1 inline-flex items-center rounded-md px-2 py-[3px] align-middle text-[11px] font-semibold leading-none tracking-tight"
                style={{ fontFamily: "var(--font-body)", background: "#2EC8B0", color: "#0e2f2a" }}
              >
                Logitech
              </span>
            )}
            {part}
          </span>
        ))}
      </span>
    </div>
  );
}
