"use client";

import { useState } from "react";
import { Space_Mono } from "next/font/google";
import { useI18n } from "@/app/i18n/context";
import { Modal } from "@/app/components/Modal";
import { useModal } from "@/app/components/Modal/hooks";

const spaceMono = Space_Mono({
  weight: ["400", "700"],
  subsets: ["latin"],
});

export function HomebrewButton() {
  const { t } = useI18n();
  const { isOpen, handleOpen, handleClose } = useModal();
  const [isCopied, setIsCopied] = useState(false);
  const command = "brew install --cask mos";

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setIsCopied(true);
      setTimeout(() => setIsCopied(false), 2000);
    } catch (err) {
      console.error("Failed to copy text: ", err);
    }
  };

  return (
    <>
      <span>•</span>
      <span
        onClick={handleOpen}
        className="cursor-pointer hover:text-white/90 transition-colors flex items-center gap-1.5"
      >
        <svg
          viewBox="0 0 24 24"
          className="w-3 h-3"
          fill="currentColor"
        >
          <path d="M20 4H4c-1.11 0-2 .9-2 2v12c0 1.1.89 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 14H4V8h16v10zm-2-1h-6v-2h6v2zM7.5 17l-1.41-1.41L8.67 13l-2.59-2.59L7.5 9l4 4-4 4z" />
        </svg>
        {t.footer_installViaHomebrew}
      </span>

      <Modal
        isOpen={isOpen}
        onClose={handleClose}
        title={t.homebrew_title}
        width="max-w-lg"
      >
        <p className="text-white/60 mb-4">{t.homebrew_description}</p>
        <div className="bg-black/30 rounded-lg p-4 flex items-center justify-between gap-4">
          <code className={`font-mono text-white/90 flex-1 flex items-center gap-2 ${spaceMono.className}`}>
            <span className="text-white/30 select-none ">$</span>
            {command}
          </code>
          <button
            onClick={handleCopy}
            className="px-3 py-1.5 bg-zinc-800 text-white/90 rounded-md hover:bg-zinc-700 transition-colors"
          >
            {isCopied ? t.homebrew_copied : t.homebrew_copy}
          </button>
        </div>
      </Modal>
    </>
  );
}