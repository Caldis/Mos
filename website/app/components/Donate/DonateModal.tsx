"use client";

import Image from "next/image";
import { useState } from "react";
import { Modal } from "@/app/components/Modal/Modal";
import { useI18n } from "@/app/i18n/context";
import { format } from "@/app/i18n/format";

const PAYPAL_URL = "https://www.paypal.me/mosapp";
const BMC_URL = "https://buymeacoffee.com/caldis";
const MEOW_URL = "https://meow.caldis.me?from=MosWebsite";

type QrChannel = "alipay" | "wechat";

const QR_SOURCES: Record<QrChannel, string> = {
  alipay: "/donate/alipay-qr.png",
  wechat: "/donate/wechat-qr.png",
};

function ExternalArrow() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      className="h-3.5 w-3.5"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
    >
      <path strokeLinecap="round" strokeLinejoin="round" d="M7 17 17 7M9 7h8v8" />
    </svg>
  );
}

interface DonateModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function DonateModal({ isOpen, onClose }: DonateModalProps) {
  const { t, language } = useI18n();
  const [channel, setChannel] = useState<QrChannel>("alipay");

  const channelName = channel === "alipay" ? t.donate.alipay : t.donate.wechat;

  const internationalChannels = [
    { href: PAYPAL_URL, label: t.donate.paypal, icon: "/donate/paypal.webp", w: 74, h: 18, cls: "h-[18px]" },
    { href: BMC_URL, label: t.donate.buyMeACoffee, icon: "/donate/bmc.svg", w: 88, h: 18, cls: "h-[26px]" },
  ];

  const qrChannels: QrChannel[] = ["alipay", "wechat"];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={t.donate.title}
      closeLabel={t.a11y.closeDialog}
      width="max-w-md"
    >
      <div className="flex flex-col gap-5">
        <p className="text-sm leading-relaxed text-white/65">{t.donate.intro}</p>

        {/* International, link-based channels */}
        <div className="grid grid-cols-2 gap-2.5">
          {internationalChannels.map((c) => (
            <a
              key={c.href}
              href={c.href}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={c.label}
              className="group relative flex items-center justify-center rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3.5 transition-colors hover:border-white/15 hover:bg-white/[0.07]"
            >
              <Image
                src={c.icon}
                alt={c.label}
                width={c.w}
                height={c.h}
                unoptimized
                className={`${c.cls} w-auto object-contain`}
              />
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-white/25 opacity-0 transition-opacity duration-200 group-hover:opacity-70">
                <ExternalArrow />
              </span>
            </a>
          ))}
        </div>

        {/* Alipay / WeChat QR — Simplified Chinese only (China-specific channels) */}
        {language === "zh" && (
          <>
            {/* Region divider */}
            <div className="flex items-center gap-3" aria-hidden="true">
              <span className="hairline h-px flex-1" />
              <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-white/40">
                {t.donate.qrLabel}
              </span>
              <span className="hairline h-px flex-1" />
            </div>

            {/* Scan-to-tip, with channel toggle */}
            <div className="flex flex-col items-center gap-3">
              <div className="flex rounded-full border border-white/[0.08] bg-white/[0.03] p-1">
                {qrChannels.map((ch) => {
                  const active = channel === ch;
                  return (
                    <button
                      key={ch}
                      type="button"
                      onClick={() => setChannel(ch)}
                      aria-pressed={active}
                      className={`flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-xs font-medium transition-colors ${
                        active ? "bg-white/[0.12] text-white" : "text-white/45 hover:text-white/75"
                      }`}
                    >
                      <Image
                        src={ch === "alipay" ? "/donate/alipay-icon.webp" : "/donate/wechat-icon.webp"}
                        alt=""
                        width={16}
                        height={16}
                        unoptimized
                        className="h-4 w-4 object-contain"
                      />
                      <span>{ch === "alipay" ? t.donate.alipay : t.donate.wechat}</span>
                    </button>
                  );
                })}
              </div>

              <div className="rounded-[20px] bg-white p-3 shadow-elevated">
                <Image
                  key={channel}
                  src={QR_SOURCES[channel]}
                  alt={channelName}
                  width={176}
                  height={176}
                  unoptimized
                  className="h-44 w-44 motion-safe:animate-[modal-appear_0.35s_var(--ease-out)]"
                />
              </div>

              <p className="font-mono text-[11px] text-white/40">
                {format(t.donate.scanHint, { app: channelName })}
              </p>
            </div>
          </>
        )}

        {/* Fat cat (meow) entry */}
        <a
          href={MEOW_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="group flex items-center gap-3 rounded-2xl border border-white/[0.08] bg-white/[0.03] px-3 py-2.5 transition-colors hover:border-white/15 hover:bg-white/[0.06]"
        >
          <Image
            src="/donate/meow.webp"
            alt=""
            width={44}
            height={44}
            unoptimized
            className="h-11 w-11 shrink-0 rounded-full object-cover object-[50%_30%] ring-1 ring-white/10"
          />
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="text-sm font-medium text-white/85">{t.donate.meowWall}</span>
            <span className="font-mono text-[11px] text-white/40">meow.caldis.me</span>
          </span>
          <span className="text-white/30 transition-all duration-200 group-hover:translate-x-0.5 group-hover:text-white/70">
            <ExternalArrow />
          </span>
        </a>
      </div>
    </Modal>
  );
}
