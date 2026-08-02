(function () {
  const DEFAULT_LANGUAGE = "zh";
  const STORAGE_KEY = "echocity_language";

  function getSavedLanguage() {
    const savedLanguage = localStorage.getItem(STORAGE_KEY);

    if (savedLanguage === "zh" || savedLanguage === "en") {
      return savedLanguage;
    }

    return DEFAULT_LANGUAGE;
  }

  function getTranslation(language, key) {
    const languagePack =
      window.EchoCityLanguages &&
      window.EchoCityLanguages[language];

    if (!languagePack) {
      return null;
    }

    return key.split(".").reduce(function (result, item) {
      if (result && Object.prototype.hasOwnProperty.call(result, item)) {
        return result[item];
      }

      return null;
    }, languagePack);
  }

  function updateText(language) {
    document.querySelectorAll("[data-i18n]").forEach(function (element) {
      const key = element.getAttribute("data-i18n");
      const translatedText = getTranslation(language, key);

      if (translatedText !== null) {
        element.textContent = translatedText;
      }
    });
  }

  function updatePlaceholders(language) {
    document
      .querySelectorAll("[data-i18n-placeholder]")
      .forEach(function (element) {
        const key = element.getAttribute("data-i18n-placeholder");
        const translatedText = getTranslation(language, key);

        if (translatedText !== null) {
          element.setAttribute("placeholder", translatedText);
        }
      });
  }

  function updateTitles(language) {
    document
      .querySelectorAll("[data-i18n-title]")
      .forEach(function (element) {
        const key = element.getAttribute("data-i18n-title");
        const translatedText = getTranslation(language, key);

        if (translatedText !== null) {
          element.setAttribute("title", translatedText);
        }
      });
  }

  function updateLanguageButton(language) {
    const languageButton = document.getElementById("languageToggle");

    if (!languageButton) {
      return;
    }

    languageButton.textContent =
      language === "zh" ? "English" : "中文";

    languageButton.setAttribute(
      "aria-label",
      language === "zh"
        ? "Switch to English"
        : "切换为中文"
    );
  }

  function applyLanguage(language) {
    const finalLanguage =
      language === "en" ? "en" : "zh";

    localStorage.setItem(STORAGE_KEY, finalLanguage);

    document.documentElement.lang =
      finalLanguage === "zh" ? "zh-CN" : "en";

    document.body.setAttribute(
      "data-language",
      finalLanguage
    );

    updateText(finalLanguage);
    updatePlaceholders(finalLanguage);
    updateTitles(finalLanguage);
    updateLanguageButton(finalLanguage);

    window.currentEchoCityLanguage = finalLanguage;

    document.dispatchEvent(
      new CustomEvent("echocityLanguageChanged", {
        detail: {
          language: finalLanguage
        }
      })
    );
  }

  function toggleLanguage() {
    const currentLanguage =
      window.currentEchoCityLanguage ||
      getSavedLanguage();

    const nextLanguage =
      currentLanguage === "zh" ? "en" : "zh";

    applyLanguage(nextLanguage);
  }

  function initializeLanguage() {
    const savedLanguage = getSavedLanguage();

    applyLanguage(savedLanguage);

    const languageButton =
      document.getElementById("languageToggle");

    if (languageButton) {
      languageButton.addEventListener(
        "click",
        toggleLanguage
      );
    }
  }

  window.EchoCityI18n = {
    applyLanguage: applyLanguage,
    toggleLanguage: toggleLanguage,
    getCurrentLanguage: function () {
      return (
        window.currentEchoCityLanguage ||
        getSavedLanguage()
      );
    },
    translate: function (key) {
      return getTranslation(
        window.currentEchoCityLanguage ||
          getSavedLanguage(),
        key
      );
    }
  };

  if (document.readyState === "loading") {
    document.addEventListener(
      "DOMContentLoaded",
      initializeLanguage
    );
  } else {
    initializeLanguage();
  }
})();