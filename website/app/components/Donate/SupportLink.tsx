"use client";

import { DonateModal } from "@/app/components/Donate/DonateModal";
import { useModal } from "@/app/components/Modal/hooks";
import { useI18n } from "@/app/i18n/context";

export function SupportLink({ className = "" }: { className?: string }) {
  const { t } = useI18n();
  const { isOpen, handleOpen, handleClose } = useModal();

  return (
    <>
      <button
        type="button"
        onClick={handleOpen}
        className={`cursor-pointer appearance-none border-0 bg-transparent p-0 transition-colors ${className}`}
      >
        {t.donate.footerLink}
      </button>

      <DonateModal isOpen={isOpen} onClose={handleClose} />
    </>
  );
}
