import type { ReactNode } from "react";
import Link from "next/link";

export function InfoPage({
  eyebrow,
  title,
  lead,
  children,
}: {
  eyebrow: string;
  title: string;
  lead: string;
  children: ReactNode;
}) {
  return (
    <main className="mx-auto max-w-5xl px-5 py-12 sm:py-16 text-white/86">
      <Link
        href="/"
        className="font-mono text-xs uppercase tracking-[0.22em] text-white/42 transition-colors hover:text-white/70"
      >
        Mos home
      </Link>
      <p className="mt-10 font-mono text-xs uppercase tracking-[0.22em] text-white/46">
        {eyebrow}
      </p>
      <h1 className="mt-4 font-display text-4xl leading-none text-white sm:text-6xl">
        {title}
      </h1>
      <p className="mt-5 max-w-3xl text-white/66 leading-7">{lead}</p>
      <div className="mt-12 space-y-12">{children}</div>
    </main>
  );
}

export function InfoSection({
  id,
  title,
  children,
}: {
  id?: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section id={id} aria-labelledby={id ? `${id}-title` : undefined}>
      <h2 id={id ? `${id}-title` : undefined} className="font-display text-2xl text-white">
        {title}
      </h2>
      <div className="mt-4 space-y-4 text-white/66 leading-7">{children}</div>
    </section>
  );
}

export function InfoList({ children }: { children: ReactNode }) {
  return <ul className="space-y-3 text-white/66 leading-7">{children}</ul>;
}

export function InfoListItem({ children }: { children: ReactNode }) {
  return (
    <li className="relative pl-5 before:absolute before:left-0 before:top-[0.72em] before:h-1.5 before:w-1.5 before:rounded-full before:bg-white/42">
      {children}
    </li>
  );
}

export function TextLink({
  href,
  children,
}: {
  href: string;
  children: ReactNode;
}) {
  const isExternal = href.startsWith("http") || href.startsWith("mailto:");
  return (
    <a
      href={href}
      target={isExternal && !href.startsWith("mailto:") ? "_blank" : undefined}
      rel={isExternal && !href.startsWith("mailto:") ? "noopener noreferrer" : undefined}
      className="text-white/88 underline decoration-white/20 underline-offset-4 transition-colors hover:text-white hover:decoration-white/45"
    >
      {children}
    </a>
  );
}
