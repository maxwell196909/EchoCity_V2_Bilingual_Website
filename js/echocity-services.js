(function (window) {
  "use strict";

  const SERVICE_VERSION = "1.0.0";

  function getStore() {
    const store =
      window.EchoCityStore ||
      window.EchoStore;

    if (!store) {
      throw new Error(
        "EchoCity Store is not available."
      );
    }

    return store;
  }
function getCollectionApi(collectionName) {
  const store = getStore();

  if (
    store[collectionName] &&
    typeof store[collectionName].create ===
      "function"
  ) {
    return store[collectionName];
  }

  if (
    store.collections &&
    store.collections[collectionName] &&
    typeof store.collections[
      collectionName
    ].create === "function"
  ) {
    return store.collections[
      collectionName
    ];
  }

  return null;
}
  function createServiceResult(
    success,
    data,
    messageKey,
    errorCode
  ) {
    return {
      success: Boolean(success),
      data: data || null,
      messageKey: messageKey || "",
      errorCode: errorCode || "",
      createdAt: new Date().toISOString()
    };
  }
function normalizeText(value) {
  return typeof value === "string"
    ? value.trim()
    : "";
}

function prepareDreamInput(input) {
  const source =
    input && typeof input === "object"
      ? input
      : {};

  return {
    title: normalizeText(source.title),
    description: normalizeText(
      source.description
    ),
    category:
      normalizeText(source.category) ||
      "general",

    creatorId:
      normalizeText(source.creatorId),

    visibility:
      normalizeText(source.visibility) ||
      "public",

    status:
      normalizeText(source.status) ||
      "published",

    sourceDevice:
      normalizeText(source.sourceDevice) ||
      "responsive"
  };
}

function validateDreamInput(dream) {
  const errors = [];

  if (!dream.title) {
    errors.push("dream.titleRequired");
  }

  if (dream.title.length > 120) {
    errors.push("dream.titleTooLong");
  }

  if (!dream.description) {
    errors.push("dream.descriptionRequired");
  }

  if (dream.description.length > 2000) {
    errors.push(
      "dream.descriptionTooLong"
    );
  }

  return {
    valid: errors.length === 0,
    errors: errors
  };
}
  const EchoServices = {
  version: SERVICE_VERSION,

  Dream: {
    prepare: function (input) {
      const dream =
        prepareDreamInput(input);

      return createServiceResult(
        true,
        dream,
        "dream.prepared",
        ""
      );
    },

    validate: function (input) {
      const dream =
        prepareDreamInput(input);

      const validation =
        validateDreamInput(dream);

      return createServiceResult(
        validation.valid,
        {
          dream: dream,
          errors: validation.errors
        },
        validation.valid
          ? "dream.valid"
          : "dream.invalid",
        validation.valid
          ? ""
          : "DREAM_VALIDATION_FAILED"
      );
    }
  },
publish: function (input) {
  const validation =
    this.validate(input);

  if (!validation.success) {
    return validation;
  }

  const dreamApi =
    getCollectionApi("dreams");

  if (!dreamApi) {
    return createServiceResult(
      false,
      {
        dream:
          validation.data.dream
      },
      "dream.storeUnavailable",
      "DREAM_STORE_NOT_AVAILABLE"
    );
  }

  try {
    const dreamData = {
      ...validation.data.dream,

      createdAt:
        new Date().toISOString(),

      updatedAt:
        new Date().toISOString(),

      progress: 0,

      sourceType: "resident"
    };

    const savedDream =
      dreamApi.create(dreamData);

    return createServiceResult(
      true,
      {
        dream: savedDream
      },
      "dream.published",
      ""
    );
  } catch (error) {
    console.error(
      "Dream publishing failed:",
      error
    );

    return createServiceResult(
      false,
      {
        dream:
          validation.data.dream
      },
      "dream.publishFailed",
      "DREAM_PUBLISH_FAILED"
    );
  }
},
  system: {
      isReady: function () {
        return Boolean(
          window.EchoCityStore ||
          window.EchoStore
        );
      },

      getStatus: function () {
        const ready = this.isReady();

        return createServiceResult(
          ready,
          {
            serviceVersion: SERVICE_VERSION,
            storeConnected: ready
          },
          ready
            ? "system.ready"
            : "system.storeUnavailable",
          ready
            ? ""
            : "STORE_NOT_AVAILABLE"
        );
      }
    }
  };

  window.EchoServices = EchoServices;
})(window);