"use client";

import { useState } from "react";

export function useModal() {
  const [isOpen, setIsOpen] = useState(false);

  const handleOpen = () => {
    setIsOpen(true);
    document.addEventListener("keydown", handleKeyDown);
  };

  const handleClose = () => {
    setIsOpen(false);
    document.removeEventListener("keydown", handleKeyDown);
  };

  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      handleClose();
    }
  };

  return {
    isOpen,
    handleOpen,
    handleClose
  };
}