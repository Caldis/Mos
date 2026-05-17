"use client";

import { useEffect } from "react";

export default function AgentModeRedirect() {
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("mode") === "agent") {
      window.location.replace("/agent/");
    }
  }, []);

  return null;
}
