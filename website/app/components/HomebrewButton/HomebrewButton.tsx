"use client";

import { useState } from "react";
import { Space_Mono, Poppins } from "next/font/google";

const spaceMono = Space_Mono({
  weight: ["400", "700"],
  subsets: ["latin"],
});

const poppins = Poppins({
  weight: ["400", "600", "700"],
  subsets: ["latin"],
});

export function HomebrewButton() {
  const [isOpen, setIsOpen] = useState(false);
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

  const handleKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape") {
      setIsOpen(false);
    }
  };

  return (
    <>
      <span>•</span>
      <span
        onClick={() => setIsOpen(true)}
        className="cursor-pointer hover:text-white/90 transition-colors"
      >
        Install via homebrew
      </span>

      {/* Modal Backdrop */}
      <div
        className={`fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center
                   transition-opacity duration-500 ease-in-out ${poppins.className}
                   ${isOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onClick={(e) => {
          if (e.target === e.currentTarget) setIsOpen(false);
        }}
        onKeyDown={handleKeyDown}
        tabIndex={0}
      >
        {/* Modal Content */}
        <div
          className={`bg-zinc-900 border border-white/10 rounded-xl w-[50vw] max-w-lg p-6 shadow-xl
                   transform transition-all duration-500 ease-in-out
                   ${isOpen ? 'scale-100 opacity-100' : 'scale-95 opacity-0'}
                   motion-safe:animate-[modal-appear_0.5s_ease-in-out]`}
        >
            {/* Header */}
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-xl font-bold text-white">Install via Homebrew</h3>
              <button
                onClick={() => setIsOpen(false)}
                className="text-white/60 hover:text-white/90 transition-colors"
              >
                <svg
                  className="w-6 h-6"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>

            {/* Description */}
            <p className="text-white/60 mb-4">Run the following command in your terminal:</p>

            {/* Command Area */}
            <div className="bg-black/30 rounded-lg p-4 flex items-center justify-between gap-4">
              <code className={`font-mono text-white/90 flex-1 flex items-center gap-2 ${spaceMono.className}`}>
                <span className="text-white/30 select-none ">$</span>
                {command}
              </code>
              <button
                onClick={handleCopy}
                className="px-3 py-1.5 bg-zinc-800 text-white/90 rounded-md hover:bg-zinc-700 transition-colors"
              >
                {isCopied ? "Copied!" : "Copy"}
              </button>
            </div>
          </div>
        </div>
    </>
  );
}