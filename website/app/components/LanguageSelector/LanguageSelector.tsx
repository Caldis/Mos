"use client";

import { Modal } from '@/app/components/Modal';
import { useModal } from '@/app/components/Modal/hooks';
import { Language, useI18n } from '@/app/i18n/context';

const LANGUAGES: {
  code: Language
  name: string
}[] = [
  { code: "en", name: "English" },
  { code: "zh", name: "简体中文" },
  { code: "zh-Hant", name: "繁體中文" },
  { code: "ja", name: "日本語" },
  { code: "ko", name: "한국어" },
  { code: "ru", name: "Русский" },
  { code: "de", name: "Deutsch" },
  { code: "pl", name: "Polski" },
  { code: "el", name: "Ελληνικά" },
  { code: "tr", name: "Türkçe" },
  { code: "uk", name: "Українська" },
  { code: "id", name: "Bahasa" },
];

export function LanguageSelector() {
  const { language, setLanguage } = useI18n();
  const { isOpen, handleOpen, handleClose } = useModal();
  const currentLanguage = LANGUAGES.find(lang => lang.code === language);

  return (
    <>
      <span>•</span>
      <button
        onClick={handleOpen}
        className="text-white/60 hover:text-white/90 transition-colors flex items-center gap-1.5"
      >
        <svg
          viewBox="0 0 24 24"
          className="w-3 h-3"
          fill="currentColor"
        >
          <path d="M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94 2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z" />
        </svg>
        <span>{currentLanguage?.name || "English"}</span>
      </button>

      <Modal
        isOpen={isOpen}
        onClose={handleClose}
        title="Select Language"
      >
        <div className="grid grid-cols-2 gap-2">
          {LANGUAGES.map((lang) => (
            <button
              key={lang.code}
              onClick={() => {
                setLanguage(lang.code);
                handleClose();
              }}
              className={`p-3 rounded-lg text-left transition-colors
                        ${language === lang.code
                          ? 'bg-white/10 text-white'
                          : 'text-white/60 hover:bg-white/5 hover:text-white/90'
                        }`}
            >
              {lang.name}
            </button>
          ))}
        </div>
      </Modal>
    </>
  );
}