"use client";

import Image from "next/image";
import { Magnetic } from "@/app/components/Magnetic/Magnetic";
import { DonateModal } from "@/app/components/Donate/DonateModal";
import { useModal } from "@/app/components/Modal/hooks";
import { useI18n } from "@/app/i18n/context";

export function SupportButton() {
  const { t } = useI18n();
  const { isOpen, handleOpen, handleClose } = useModal();

  return (
    <>
      <Magnetic strength={14}>
        <button
          type="button"
          onClick={handleOpen}
          className="group grid h-11 w-11 place-items-center rounded-2xl border border-white/5 bg-white/4 hover:bg-white/7 hover:border-white/9 transition-colors"
          aria-label={t.donate.trigger}
          title={t.donate.trigger}
        >
          <Image
            src="/donate/meow.webp"
            alt=""
            width={28}
            height={28}
            unoptimized
            className="h-7 w-7 rounded-full object-cover object-[50%_30%] ring-1 ring-white/15 motion-safe:animate-[meow-heartbeat_1.8s_ease-in-out_infinite] group-hover:[animation-duration:0.9s]"
          />
        </button>
      </Magnetic>

      <DonateModal isOpen={isOpen} onClose={handleClose} />
    </>
  );
}
