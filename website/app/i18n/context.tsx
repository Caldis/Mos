"use client";

import { createContext, useContext, useEffect, useState } from 'react';

import { de } from './de';
import { el } from './el';
import { en } from './en';
import { id } from './id';
import { ja } from './ja';
import { ko } from './ko';
import { ru } from './ru';
import { tr } from './tr';
import { uk } from './uk';
import { zh } from './zh';
import { zhHant } from './zh-Hant';

export type Language = "en" | "zh" | "ru" | "tr" | "ko" | "de" | "el" | "uk" | "ja" | "zh-Hant" | "id";
export type Translations = typeof en;

interface I18nContextType {
  language: Language;
  t: Translations;
  setLanguage: (lang: Language) => void;
}

const I18nContext = createContext<I18nContextType | null>(null);

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [language, setLanguage] = useState<Language>("en");
  const [translations, setTranslations] = useState<Translations>(en);

  useEffect(() => {
    // 从本地存储中获取语言偏好
    const storedLanguage = localStorage.getItem("language") as Language;
    if (storedLanguage) {
      setLanguage(storedLanguage);
    } else {
      // 根据浏览器语言设置默认语言
      const browserLang = navigator.language.toLowerCase();
      setLanguage(browserLang.startsWith("zh") ? "zh" : "en");
    }
  }, []);

  useEffect(() => {
    // 更新翻译内容
    const translations = {
      en,
      zh,
      ru,
      tr,
      ko,
      de,
      el,
      uk,
      ja,
      "zh-Hant": zhHant,
      id,
    }[language] || en;
    setTranslations(translations);
    // 保存语言偏好到本地存储
    localStorage.setItem("language", language);
  }, [language]);

  return (
    <I18nContext.Provider value={{ language, t: translations, setLanguage }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error("useI18n must be used within an I18nProvider");
  }
  return context;
}