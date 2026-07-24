/*
  EchoCity Unified Data Store
  EchoCity 统一数据存储中心

  所有页面以后通过 EchoStore 读写数据，
  不再分别建立多个 localStorage 名称。
*/

(function () {
  "use strict";

  const DATABASE_KEY = "echocity_db";
  const DATABASE_VERSION = 1;

  function createEmptyDatabase() {
    return {
      version: DATABASE_VERSION,

      residents: [],
      activities: [],
      messages: [],
      attachments: [],
      places: [],
      memories: [],

      settings: {
        language:
          localStorage.getItem("echocityLanguage") || "zh",

        currentResidentId: "resident_maxwell"
      },

      metadata: {
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      }
    };
  }

  function cloneData(data) {
    return JSON.parse(JSON.stringify(data));
  }

  function generateId(prefix) {
    const timestamp = Date.now().toString(36);

    const randomValue = Math.random()
      .toString(36)
      .slice(2, 8);

    return `${prefix}_${timestamp}_${randomValue}`;
  }

  function isValidDatabase(database) {
    if (!database || typeof database !== "object") {
      return false;
    }

    const requiredCollections = [
      "residents",
      "activities",
      "messages",
      "attachments",
      "places",
      "memories"
    ];

    return requiredCollections.every((collectionName) => {
      return Array.isArray(database[collectionName]);
    });
  }

  function normalizeDatabase(database) {
    const emptyDatabase = createEmptyDatabase();

    return {
      ...emptyDatabase,
      ...database,

      residents: Array.isArray(database.residents)
        ? database.residents
        : [],

      activities: Array.isArray(database.activities)
        ? database.activities
        : [],

      messages: Array.isArray(database.messages)
        ? database.messages
        : [],

      attachments: Array.isArray(database.attachments)
        ? database.attachments
        : [],

      places: Array.isArray(database.places)
        ? database.places
        : [],

      memories: Array.isArray(database.memories)
        ? database.memories
        : [],

      settings: {
        ...emptyDatabase.settings,
        ...(database.settings || {})
      },

      metadata: {
        ...emptyDatabase.metadata,
        ...(database.metadata || {})
      }
    };
  }  function loadDatabase() {
    const savedValue =
      localStorage.getItem(DATABASE_KEY);

    if (!savedValue) {
      const newDatabase =
        createEmptyDatabase();

      saveDatabase(newDatabase);

      return newDatabase;
    }

    try {
      const parsedDatabase =
        JSON.parse(savedValue);

      if (!isValidDatabase(parsedDatabase)) {
        throw new Error(
          "Invalid EchoCity database structure."
        );
      }

      return normalizeDatabase(parsedDatabase);
    } catch (error) {
      console.warn(
        "EchoCity database could not be loaded.",
        error
      );

      const backupKey =
        `${DATABASE_KEY}_backup_${Date.now()}`;

      localStorage.setItem(
        backupKey,
        savedValue
      );

      const newDatabase =
        createEmptyDatabase();

      saveDatabase(newDatabase);

      return newDatabase;
    }
  }

  function saveDatabase(database) {
    const normalizedDatabase =
      normalizeDatabase(database);

    normalizedDatabase.version =
      DATABASE_VERSION;

    normalizedDatabase.metadata.updatedAt =
      new Date().toISOString();

    localStorage.setItem(
      DATABASE_KEY,
      JSON.stringify(normalizedDatabase)
    );

    window.dispatchEvent(
      new CustomEvent(
        "echocity:database-updated",
        {
          detail: cloneData(
            normalizedDatabase
          )
        }
      )
    );

    return cloneData(
      normalizedDatabase
    );
  }

  function resetDatabase() {
    const newDatabase =
      createEmptyDatabase();

    return saveDatabase(newDatabase);
  }

  function getDatabase() {
    return cloneData(
      loadDatabase()
    );
  }

  function getCollection(collectionName) {
    const database =
      loadDatabase();

    const collection =
      database[collectionName];

    if (!Array.isArray(collection)) {
      throw new Error(
        `Unknown EchoCity collection: ${collectionName}`
      );
    }

    return cloneData(collection);
  }

  function findById(
    collectionName,
    itemId
  ) {
    if (!itemId) {
      return null;
    }

    const collection =
      getCollection(collectionName);

    const foundItem =
      collection.find(
        (item) => item.id === itemId
      );

    return foundItem
      ? cloneData(foundItem)
      : null;
  }

  function findMany(
    collectionName,
    filterFunction
  ) {
    const collection =
      getCollection(collectionName);

    if (
      typeof filterFunction !==
      "function"
    ) {
      return collection;
    }

    return collection.filter(
      filterFunction
    );
  }

  function createItem(
    collectionName,
    itemData,
    idPrefix
  ) {
    const database =
      loadDatabase();

    if (
      !Array.isArray(
        database[collectionName]
      )
    ) {
      throw new Error(
        `Unknown EchoCity collection: ${collectionName}`
      );
    }

    const now =
      new Date().toISOString();

    const newItem = {
      ...cloneData(itemData),
      id:
        itemData.id ||
        generateId(
          idPrefix ||
          collectionName.slice(0, -1)
        ),
      createdAt:
        itemData.createdAt || now,
      updatedAt: now
    };

    database[collectionName].push(
      newItem
    );

    saveDatabase(database);

    return cloneData(newItem);
  }

  function updateItem(
    collectionName,
    itemId,
    changes
  ) {
    const database =
      loadDatabase();

    const collection =
      database[collectionName];

    if (!Array.isArray(collection)) {
      throw new Error(
        `Unknown EchoCity collection: ${collectionName}`
      );
    }

    const itemIndex =
      collection.findIndex(
        (item) => item.id === itemId
      );

    if (itemIndex === -1) {
      return null;
    }

    const updatedItem = {
      ...collection[itemIndex],
      ...cloneData(changes),
      id: collection[itemIndex].id,
      createdAt:
        collection[itemIndex].createdAt,
      updatedAt:
        new Date().toISOString()
    };

    collection[itemIndex] =
      updatedItem;

    saveDatabase(database);

    return cloneData(updatedItem);
  }  function deleteItem(
    collectionName,
    itemId
  ) {
    const database =
      loadDatabase();

    const collection =
      database[collectionName];

    if (!Array.isArray(collection)) {
      throw new Error(
        `Unknown EchoCity collection: ${collectionName}`
      );
    }

    const itemIndex =
      collection.findIndex(
        (item) => item.id === itemId
      );

    if (itemIndex === -1) {
      return false;
    }

    collection.splice(itemIndex, 1);

    saveDatabase(database);

    return true;
  }

  function replaceCollection(
    collectionName,
    items
  ) {
    const database =
      loadDatabase();

    if (
      !Array.isArray(
        database[collectionName]
      )
    ) {
      throw new Error(
        `Unknown EchoCity collection: ${collectionName}`
      );
    }

    if (!Array.isArray(items)) {
      throw new Error(
        "Collection data must be an array."
      );
    }

    database[collectionName] =
      cloneData(items);

    saveDatabase(database);

    return getCollection(
      collectionName
    );
  }

  function upsertItem(
    collectionName,
    itemData,
    idPrefix
  ) {
    if (
      !itemData ||
      typeof itemData !== "object"
    ) {
      throw new Error(
        "EchoCity item data must be an object."
      );
    }

    if (itemData.id) {
      const existingItem =
        findById(
          collectionName,
          itemData.id
        );

      if (existingItem) {
        return updateItem(
          collectionName,
          itemData.id,
          itemData
        );
      }
    }

    return createItem(
      collectionName,
      itemData,
      idPrefix
    );
  }

  function getSetting(settingName) {
    const database =
      loadDatabase();

    return database.settings[
      settingName
    ];
  }

  function setSetting(
    settingName,
    settingValue
  ) {
    const database =
      loadDatabase();

    database.settings[
      settingName
    ] = cloneData(settingValue);

    saveDatabase(database);

    if (
      settingName === "language"
    ) {
      localStorage.setItem(
        "echocityLanguage",
        String(settingValue)
      );
    }

    return cloneData(
      database.settings
    );
  }

  function getCurrentResident() {
    const currentResidentId =
      getSetting(
        "currentResidentId"
      );

    if (!currentResidentId) {
      return null;
    }

    return findById(
      "residents",
      currentResidentId
    );
  }

  function setCurrentResident(
    residentId
  ) {
    const resident =
      findById(
        "residents",
        residentId
      );

    if (!resident) {
      return null;
    }

    setSetting(
      "currentResidentId",
      residentId
    );

    return resident;
  }

  function createCollectionApi(
    collectionName,
    idPrefix
  ) {
    return {
      all() {
        return getCollection(
          collectionName
        );
      },

      getById(itemId) {
        return findById(
          collectionName,
          itemId
        );
      },

      find(filterFunction) {
        return findMany(
          collectionName,
          filterFunction
        );
      },

      create(itemData) {
        return createItem(
          collectionName,
          itemData,
          idPrefix
        );
      },

      update(
        itemId,
        changes
      ) {
        return updateItem(
          collectionName,
          itemId,
          changes
        );
      },

      upsert(itemData) {
        return upsertItem(
          collectionName,
          itemData,
          idPrefix
        );
      },

      remove(itemId) {
        return deleteItem(
          collectionName,
          itemId
        );
      },

      replace(items) {
        return replaceCollection(
          collectionName,
          items
        );
      }
    };
  }

  const collectionApis = {
    residents:
      createCollectionApi(
        "residents",
        "resident"
      ),

    activities:
      createCollectionApi(
        "activities",
        "activity"
      ),

    messages:
      createCollectionApi(
        "messages",
        "message"
      ),

    attachments:
      createCollectionApi(
        "attachments",
        "attachment"
      ),

    places:
      createCollectionApi(
        "places",
        "place"
      ),

    memories:
      createCollectionApi(
        "memories",
        "memory"
      )
  };  function migrateLegacyData() {
    const database =
      loadDatabase();

    let databaseChanged = false;

    const legacyMemoryKeys = [
      "echocityBasketballMemory",
      "basketballMemory",
      "echocitySharedMemories",
      "sharedMemories"
    ];

    legacyMemoryKeys.forEach(
      (legacyKey) => {
        const legacyValue =
          localStorage.getItem(
            legacyKey
          );

        if (!legacyValue) {
          return;
        }

        try {
          const parsedValue =
            JSON.parse(legacyValue);

          const legacyMemories =
            Array.isArray(parsedValue)
              ? parsedValue
              : [parsedValue];

          legacyMemories.forEach(
            (legacyMemory) => {
              if (
                !legacyMemory ||
                typeof legacyMemory !==
                  "object"
              ) {
                return;
              }

              const legacyIdentity =
                legacyMemory.id ||
                legacyMemory.createdAt ||
                [
                  legacyMemory.type,
                  legacyMemory.titleZh,
                  legacyMemory.score
                ].join("|");

              const alreadyImported =
                database.memories.some(
                  (memory) =>
                    memory.legacyIdentity ===
                    legacyIdentity
                );

              if (alreadyImported) {
                return;
              }

              const activityId =
                generateId("activity");

              const memoryId =
                generateId("memory");

              const now =
                legacyMemory.createdAt ||
                new Date().toISOString();

              const activity = {
                id: activityId,

                type:
                  legacyMemory.type ||
                  "shared_activity",

                creatorId:
                  "resident_maxwell",

                title: {
                  zh:
                    legacyMemory.titleZh ||
                    legacyMemory.title ||
                    "共同活动",

                  en:
                    legacyMemory.titleEn ||
                    legacyMemory.title ||
                    "Shared Activity"
                },

                description: {
                  zh:
                    legacyMemory.descriptionZh ||
                    "由旧版 EchoCity 记录迁移而来。",

                  en:
                    legacyMemory.descriptionEn ||
                    "Migrated from an earlier EchoCity record."
                },

                placeId: null,

                location: {
                  zh:
                    legacyMemory.courtZh ||
                    legacyMemory.locationZh ||
                    legacyMemory.court ||
                    legacyMemory.location ||
                    "地点未记录",

                  en:
                    legacyMemory.courtEn ||
                    legacyMemory.locationEn ||
                    legacyMemory.court ||
                    legacyMemory.location ||
                    "Location not recorded"
                },

                participantIds: [],

                participantCount:
                  Number(
                    legacyMemory.participants
                  ) || 0,

                status:
                  legacyMemory.status ||
                  "completed",

                result: {
                  score:
                    legacyMemory.score ||
                    "",

                  duration:
                    Number(
                      legacyMemory.duration
                    ) || 0
                },

                createdAt: now,
                updatedAt: now
              };

              const memory = {
                id: memoryId,
                activityId,
                ownerIds: [
                  "resident_maxwell"
                ],

                summary: {
                  zh:
                    legacyMemory.summaryZh ||
                    legacyMemory.echoSummaryZh ||
                    "这段共同经历已经保存进入 EchoCity。",

                  en:
                    legacyMemory.summaryEn ||
                    legacyMemory.echoSummaryEn ||
                    "This shared experience has been preserved in EchoCity."
                },

                messageIds: [],
                attachmentIds: [],

                createdBy:
                  "echo",

                legacyIdentity,

                createdAt: now,
                updatedAt: now
              };

              database.activities.push(
                activity
              );

              database.memories.push(
                memory
              );

              databaseChanged = true;
            }
          );
        } catch (error) {
          console.warn(
            "Unable to migrate legacy data:",
            legacyKey,
            error
          );
        }
      }
    );

    if (databaseChanged) {
      saveDatabase(database);
    }

    return databaseChanged;
  }

  function initializeDefaultData() {
    const database =
      loadDatabase();

    let databaseChanged = false;

    const defaultResidents = [
      {
        id: "resident_maxwell",
        name: "Maxwell Cheng",
        initials: "MC",
        country: "China",
        city: "Nanjing",
        languages: [
          "zh",
          "en"
        ],
        interests: [
          "basketball",
          "faith",
          "engineering"
        ],
        status: "active"
      },
      {
        id: "resident_anna",
        name: "Anna",
        initials: "AN",
        status: "active"
      },
      {
        id: "resident_david",
        name: "David",
        initials: "DV",
        status: "active"
      },
      {
        id: "resident_jack",
        name: "Jack",
        initials: "JK",
        status: "active"
      },
      {
        id: "resident_lucy",
        name: "Lucy",
        initials: "LC",
        status: "active"
      },
      {
        id: "resident_tom",
        name: "Tom",
        initials: "TM",
        status: "active"
      }
    ];

    defaultResidents.forEach(
      (resident) => {
        const residentExists =
          database.residents.some(
            (item) =>
              item.id === resident.id
          );

        if (!residentExists) {
          const now =
            new Date().toISOString();

          database.residents.push({
            ...resident,
            createdAt: now,
            updatedAt: now
          });

          databaseChanged = true;
        }
      }
    );

    const defaultPlace = {
      id: "place_hexi_gym",

      name: {
        zh: "河西体育馆",
        en: "Hexi Gym"
      },

      address: {
        zh: "南京市建邺区",
        en: "Jianye District, Nanjing"
      },

      latitude: 32.041,
      longitude: 118.735,
      status: "active"
    };

    const placeExists =
      database.places.some(
        (place) =>
          place.id ===
          defaultPlace.id
      );

    if (!placeExists) {
      const now =
        new Date().toISOString();

      database.places.push({
        ...defaultPlace,
        createdAt: now,
        updatedAt: now
      });

      databaseChanged = true;
    }

    if (databaseChanged) {
      saveDatabase(database);
    }

    return getDatabase();
  }
  function getSimpleResidents() {
    return getCollection("residents").map(
      (resident) => ({
        id: resident.id,
        name: resident.name,
        country:
          resident.country || "",
        city:
          resident.city || "",
        interests:
          Array.isArray(
            resident.interests
          )
            ? resident.interests
            : [],
        status:
          resident.status || "active"
      })
    );
  }
  const EchoStore = {
    version:
      DATABASE_VERSION,

    key:
      DATABASE_KEY,

    load:
      loadDatabase,

    save:
      saveDatabase,

    getDatabase,

    reset:
      resetDatabase,

    generateId,

    settings: {
      get:
        getSetting,

      set:
        setSetting
    },

    currentResident: {
      get:
        getCurrentResident,

      set:
        setCurrentResident
    },

    residents: {
  ...collectionApis.residents,

  simple:
    getSimpleResidents
},

    activities:
      collectionApis.activities,

    messages:
      collectionApis.messages,

    attachments:
      collectionApis.attachments,

    places:
      collectionApis.places,

    memories:
      collectionApis.memories,

    migrateLegacyData,

    initializeDefaultData
  };

  window.EchoStore =
    EchoStore;

  migrateLegacyData();
  initializeDefaultData();

  window.dispatchEvent(
    new CustomEvent(
      "echocity:store-ready",
      {
        detail: {
          version:
            DATABASE_VERSION,

          database:
            getDatabase()
        }
      }
    )
  );
})();