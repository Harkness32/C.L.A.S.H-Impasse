/*
    C.L.A.S.H. base store -- page logic.

    Talks to SQF over two channels only:

      page -> SQF   A3API.SendAlert(JSON.stringify({event, data}))
                    Fires the control's JSDialog event handler. The engine
                    TRUNCATES this at 10240 characters and the loss is silent,
                    so anything unbounded (the cart) is sent in chunks and
                    every outbound message is measured before it leaves.

      SQF -> page   ExecJS calling CLASHStore.receive(event, payload)

    The sandbox blocks fetch, XMLHttpRequest, localStorage and IndexedDB. All
    state round-trips through SQF; saved loadouts live in the Arma profile.
*/

window.CLASHStore = (function () {
  "use strict";

  /* The engine's page->SQF cap. Chunks are sized well under it to leave room
     for the JSON envelope and any multi-byte escaping. */
  var MESSAGE_CAP = 10240;
  var CHUNK_BUDGET = 6000;
  var MAX_CONCURRENT_TEXTURES = 6;

  /* How long to wait for the server's verdict before letting the player try
     again. Without this the Purchase button latches disabled forever if the
     reply never arrives -- a dropped response, a disconnect, or any server
     path that returns without answering. */
  var CHECKOUT_TIMEOUT_MS = 20000;

  var state = {
    categories: [],
    currentCategory: "",
    categoryLabel: "Equipment",
    items: [],
    cart: [],
    selectedItem: null,
    activeContainer: "auto",
    pendingAttachmentAdd: null,
    balance: 0,
    economyEnabled: false,
    checkoutPending: false,
    checkoutTimer: 0,
    query: "",
    loadouts: [],
    sequence: 0,
  };

  var containerLabels = {
    auto: "Equip",
    uniform: "Uniform",
    vest: "Vest",
    backpack: "Backpack",
  };

  var packableCategories = {
    uniforms: true,
    vests: true,
    headgear: true,
    facewear: true,
    ammo: true,
    mines: true,
    attachments: true,
    misc: true,
  };

  var vehicleCategories = {
    cars: true,
    armor: true,
    helis: true,
    planes: true,
    naval: true,
    static: true,
    other: true,
  };

  var categorySymbols = {
    primary: "PRI",
    handgun: "PST",
    secondary: "LCH",
    uniforms: "UNI",
    vests: "VST",
    headgear: "HLM",
    facewear: "FCE",
    backpacks: "BPK",
    ammo: "AMM",
    mines: "MIN",
    misc: "ITM",
    attachments: "ATT",
    cars: "CAR",
    armor: "ARM",
    helis: "HEL",
    planes: "PLN",
    naval: "NAV",
    static: "STA",
    other: "OTH",
  };

  var textureCache = {};
  var textureRequests = {};
  var queuedTexturePaths = [];
  var queuedTextureLookup = {};
  var activeTextureRequests = 0;
  var textureObserver = null;
  var messageTimer = 0;

  var scrollContainerIds = [
    "categoryList",
    "itemList",
    "cartList",
    "itemDetails",
    "loadoutList",
    "attachmentList",
  ];

  /* ------------------------------------------------------------ plumbing -- */

  function node(id) {
    return document.getElementById(id);
  }

  function text(id, value) {
    var target = node(id);
    if (target) {
      target.textContent = value;
    }
  }

  function clear(target) {
    while (target && target.firstChild) {
      target.removeChild(target.firstChild);
    }
  }

  function el(tag, className, content) {
    var n = document.createElement(tag);
    if (className) {
      n.className = className;
    }
    if (content !== undefined) {
      n.textContent = String(content);
    }
    return n;
  }

  function sendRaw(payload) {
    if (payload.length > MESSAGE_CAP) {
      /* Returning false lets callers split further rather than handing the
         engine a message it will quietly cut in half. */
      return false;
    }
    if (typeof A3API !== "undefined" && A3API.SendAlert) {
      A3API.SendAlert(payload);
    }
    return true;
  }

  function send(event, data) {
    return sendRaw(JSON.stringify({ event: event, data: data || {} }));
  }

  function message(value, kind) {
    var target = node("message");
    if (!target) {
      return;
    }
    if (messageTimer) {
      window.clearTimeout(messageTimer);
      messageTimer = 0;
    }
    target.textContent = value;
    target.className = "message" + (kind ? " " + kind : "");
    if (kind === "good") {
      messageTimer = window.setTimeout(function () {
        target.textContent = "";
        target.className = "message";
        messageTimer = 0;
      }, 6000);
    }
  }

  function groupDigits(value) {
    return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  function money(value) {
    var amount = Math.round(Number(value) || 0);
    return groupDigits(amount);
  }

  function priceLabel(value) {
    if (!state.economyEnabled) {
      return "";
    }
    return money(value);
  }

  function itemPrice(item) {
    var value = Number(item && item.priceValue);
    return isFinite(value) ? value : 0;
  }

  function readable(value) {
    return String(value || "Unknown")
      .toLowerCase()
      .replace(/_/g, " ")
      .replace(/^./, function (c) {
        return c.toUpperCase();
      });
  }

  /* -------------------------------------------------------- scroll state -- */

  function scrollSnapshot() {
    var snapshot = {};
    scrollContainerIds.forEach(function (id) {
      var target = node(id);
      if (target) {
        snapshot[id] = target.scrollTop;
      }
    });
    return snapshot;
  }

  function restoreScroll(snapshot, onlyIds) {
    if (!snapshot) {
      return;
    }
    Object.keys(snapshot).forEach(function (id) {
      if (onlyIds && onlyIds.indexOf(id) === -1) {
        return;
      }
      var target = node(id);
      if (target) {
        target.scrollTop = snapshot[id];
      }
    });
  }

  function focusedButtonIndex(root) {
    if (!root) {
      return -1;
    }
    return Array.prototype.indexOf.call(
      root.querySelectorAll("button"),
      document.activeElement,
    );
  }

  function restoreButtonFocus(root, index) {
    if (!root || index < 0) {
      return;
    }
    var buttons = root.querySelectorAll("button");
    var target = buttons[Math.min(index, buttons.length - 1)];
    if (target) {
      target.focus({ preventScroll: true });
    }
  }

  /* ------------------------------------------------------------ textures -- */

  function isTextureSource(path) {
    var value = String(path || "").trim().toLowerCase();
    /* A bad path does not reject: RequestTexture resolves with a short stub
       that reads as success. Only accept something that is actually an image. */
    return (
      value.indexOf("data:image/") === 0 ||
      value.indexOf("blob:") === 0 ||
      value.indexOf("http://") === 0 ||
      value.indexOf("https://") === 0
    );
  }

  function normalizeTexturePath(path) {
    var normalized = String(path || "").trim();
    if (!normalized) {
      return "";
    }
    while (normalized.charAt(0) === "\\" || normalized.charAt(0) === "/") {
      normalized = normalized.slice(1);
    }
    if (!/\.[A-Za-z0-9]+$/.test(normalized)) {
      normalized += ".paa";
    }
    return normalized;
  }

  function drawTextureNode(target, source) {
    var symbol = target.getAttribute("data-symbol") || "";
    clear(target);
    if (source) {
      var image = document.createElement("img");
      image.className = "texture-img";
      image.alt = "";
      image.src = source;
      target.appendChild(image);
      return;
    }
    target.appendChild(el("div", "media-fallback", symbol));
  }

  function applyTextureToNodes(path, source) {
    var targets = document.querySelectorAll("[data-texture-path]");
    var i;
    for (i = 0; i < targets.length; i += 1) {
      if (targets[i].getAttribute("data-texture-path") === path) {
        drawTextureNode(targets[i], source);
      }
    }
  }

  function finishTextureRequest(path, source) {
    var resolved = String(source || "").trim();
    if (!isTextureSource(resolved)) {
      resolved = "";
    }
    textureCache[path] = resolved;
    applyTextureToNodes(path, resolved);
  }

  function pumpTextureQueue() {
    if (typeof A3API === "undefined" || typeof A3API.RequestTexture !== "function") {
      return;
    }
    while (
      activeTextureRequests < MAX_CONCURRENT_TEXTURES &&
      queuedTexturePaths.length
    ) {
      startTextureRequest(queuedTexturePaths.shift());
    }
  }

  function startTextureRequest(path) {
    var result;
    delete queuedTextureLookup[path];
    activeTextureRequests += 1;
    textureRequests[path] = true;

    function done(source) {
      finishTextureRequest(path, source);
      activeTextureRequests = Math.max(0, activeTextureRequests - 1);
      delete textureRequests[path];
      pumpTextureQueue();
    }

    try {
      result = A3API.RequestTexture(path, 512);
    } catch (error) {
      done("");
      return;
    }

    if (result && typeof result.then === "function") {
      result.then(done, function () {
        done("");
      });
    } else {
      done(result);
    }
  }

  function queueTextureRequest(path) {
    if (
      !path ||
      Object.prototype.hasOwnProperty.call(textureCache, path) ||
      textureRequests[path] ||
      queuedTextureLookup[path]
    ) {
      return;
    }
    queuedTextureLookup[path] = true;
    queuedTexturePaths.push(path);
    pumpTextureQueue();
  }

  function ensureTextureObserver() {
    if (textureObserver || typeof IntersectionObserver === "undefined") {
      return;
    }
    textureObserver = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) {
            return;
          }
          var path = entry.target.getAttribute("data-texture-path");
          textureObserver.unobserve(entry.target);
          queueTextureRequest(path);
        });
      },
      { rootMargin: "120px" },
    );
  }

  function renderTextureBox(className, path, symbol) {
    var box = el("div", className);
    box.setAttribute("data-symbol", symbol || "");
    var normalized = normalizeTexturePath(path);

    if (!normalized) {
      drawTextureNode(box, "");
      return box;
    }

    box.setAttribute("data-texture-path", normalized);

    if (Object.prototype.hasOwnProperty.call(textureCache, normalized)) {
      drawTextureNode(box, textureCache[normalized]);
      return box;
    }

    drawTextureNode(box, "");
    ensureTextureObserver();
    if (textureObserver) {
      textureObserver.observe(box);
    } else {
      queueTextureRequest(normalized);
    }
    return box;
  }

  /* ---------------------------------------------------------------- cart -- */

  function canPack(item) {
    return !!packableCategories[item.category];
  }

  function isVehicle(item) {
    return !!vehicleCategories[item.category] || item.entryKind === "vehicle";
  }

  function includedAttachments(item) {
    var list = item && item.includedAttachments;
    return Array.isArray(list) ? list : [];
  }

  function normalizeContainer(item, container) {
    if (!canPack(item)) {
      return "auto";
    }
    return containerLabels[container] ? container : "auto";
  }

  function cartKey(line) {
    return [
      line.className,
      line.entryKind,
      line.category,
      line.container,
      (line.attachments || []).join("+"),
    ].join("|");
  }

  function findCartLine(line) {
    var key = cartKey(line);
    var i;
    for (i = 0; i < state.cart.length; i += 1) {
      if (cartKey(state.cart[i]) === key) {
        return state.cart[i];
      }
    }
    return null;
  }

  function addToCart(item, container, attachments) {
    var line = {
      className: item.className,
      name: item.name,
      entryKind: item.entryKind,
      category: item.category,
      container: normalizeContainer(item, container),
      quantity: 1,
      priceValue: itemPrice(item),
      attachments: attachments || [],
    };

    var existing = findCartLine(line);
    if (existing) {
      existing.quantity += 1;
    } else {
      state.cart.push(line);
    }
    renderCart();
    updateSummary();
  }

  function lineTotal(line) {
    var attachmentCost = (line.attachments || []).reduce(function (sum, entry) {
      return sum + (Number(entry && entry.priceValue) || 0);
    }, 0);
    return (line.priceValue + attachmentCost) * line.quantity;
  }

  function cartTotal() {
    return state.cart.reduce(function (sum, line) {
      return sum + lineTotal(line);
    }, 0);
  }

  function cartQuantity() {
    return state.cart.reduce(function (sum, line) {
      return sum + line.quantity;
    }, 0);
  }

  function updateSummary() {
    var total = cartTotal();
    var quantity = cartQuantity();

    text(
      "cartSummary",
      state.economyEnabled
        ? quantity + " / " + money(total)
        : String(quantity),
    );
    text("balance", state.economyEnabled ? money(state.balance) : "—");

    var reason = "";
    if (state.checkoutPending) {
      reason = "Purchase in progress…";
    } else if (!quantity) {
      reason = "";
    } else if (state.economyEnabled && total > state.balance) {
      reason = "Insufficient funds.";
    }
    text("checkoutReason", reason);

    var button = node("checkoutButton");
    if (button) {
      button.disabled =
        state.checkoutPending ||
        !quantity ||
        (state.economyEnabled && total > state.balance);
    }
  }

  function renderContainerRow(line) {
    var row = el("div", "container-row");
    Object.keys(containerLabels).forEach(function (key) {
      var chip = el("button", "chip" + (line.container === key ? " selected" : ""), containerLabels[key]);
      chip.type = "button";
      chip.addEventListener("click", function () {
        line.container = key;
        /* The new destination may collide with a line already in the cart;
           fold this one into it rather than showing the same thing twice. */
        var i;
        for (i = 0; i < state.cart.length; i += 1) {
          if (state.cart[i] !== line && cartKey(state.cart[i]) === cartKey(line)) {
            state.cart[i].quantity += line.quantity;
            state.cart.splice(state.cart.indexOf(line), 1);
            break;
          }
        }
        renderCart();
        updateSummary();
      });
      row.appendChild(chip);
    });
    return row;
  }

  function renderCart() {
    var list = node("cartList");
    if (!list) {
      return;
    }
    var snapshot = scrollSnapshot();
    var focusIndex = focusedButtonIndex(list);
    clear(list);

    if (!state.cart.length) {
      list.appendChild(el("div", "empty", "Nothing selected."));
      restoreScroll(snapshot, ["cartList"]);
      return;
    }

    state.cart.forEach(function (line) {
      var row = el("div", "cart-line");

      var title = el("div", "line-title");
      title.appendChild(el("span", "name", line.name));
      if (state.economyEnabled) {
        title.appendChild(el("span", "item-price", money(lineTotal(line))));
      }
      row.appendChild(title);

      var metaParts = [readable(line.category)];
      if (canPack(line) && line.container !== "auto") {
        metaParts.push("to " + containerLabels[line.container]);
      }
      if ((line.attachments || []).length) {
        metaParts.push((line.attachments || []).length + " attachment(s)");
      }
      row.appendChild(el("div", "meta", metaParts.join(" · ")));

      var bottom = el("div", "cart-bottom");
      var qty = el("div", "qty");

      var minus = el("button", "", "−");
      minus.type = "button";
      minus.addEventListener("click", function () {
        line.quantity -= 1;
        if (line.quantity <= 0) {
          state.cart.splice(state.cart.indexOf(line), 1);
        }
        renderCart();
        updateSummary();
      });

      var plus = el("button", "", "+");
      plus.type = "button";
      plus.addEventListener("click", function () {
        line.quantity += 1;
        renderCart();
        updateSummary();
      });

      qty.appendChild(minus);
      qty.appendChild(el("span", "", line.quantity));
      qty.appendChild(plus);
      bottom.appendChild(qty);

      var remove = el("button", "", "Remove");
      remove.type = "button";
      remove.addEventListener("click", function () {
        state.cart.splice(state.cart.indexOf(line), 1);
        renderCart();
        updateSummary();
      });
      bottom.appendChild(remove);
      row.appendChild(bottom);

      if (canPack(line)) {
        row.appendChild(renderContainerRow(line));
      }

      list.appendChild(row);
    });

    restoreScroll(snapshot, ["cartList"]);
    restoreButtonFocus(list, focusIndex);
  }

  /* ---------------------------------------------------------- categories -- */

  function renderCategories() {
    var rail = node("categoryList");
    if (!rail) {
      return;
    }
    var snapshot = scrollSnapshot();
    clear(rail);

    state.categories.forEach(function (category) {
      var button = el(
        "button",
        "category" + (category.id === state.currentCategory ? " selected" : ""),
      );
      button.type = "button";
      button.title = category.label + " (" + (category.count || 0) + ")";
      button.setAttribute("aria-label", button.title);
      button.setAttribute(
        "aria-selected",
        category.id === state.currentCategory ? "true" : "false",
      );
      button.disabled = !category.count;
      button.appendChild(
        renderTextureBox(
          "category-icon",
          category.icon,
          categorySymbols[category.id] || category.label.slice(0, 3).toUpperCase(),
        ),
      );
      button.addEventListener("click", function () {
        selectCategory(category.id);
      });
      rail.appendChild(button);
    });

    restoreScroll(snapshot, ["categoryList"]);
  }

  function selectCategory(id) {
    if (!id || id === state.currentCategory) {
      return;
    }
    state.currentCategory = id;
    state.items = [];
    state.selectedItem = null;
    renderCategories();
    renderItems();
    renderDetails();
    send("store::category", { category: id });
  }

  /* --------------------------------------------------------- destinations -- */

  function renderTargetButtons() {
    var row = node("targetRow");
    if (!row) {
      return;
    }
    clear(row);

    Object.keys(containerLabels).forEach(function (key) {
      var chip = el(
        "button",
        "chip" + (state.activeContainer === key ? " selected" : ""),
        containerLabels[key].slice(0, 3).toUpperCase(),
      );
      chip.type = "button";
      chip.title = "Add packable gear to: " + containerLabels[key];
      chip.setAttribute("aria-label", chip.title);
      chip.addEventListener("click", function () {
        state.activeContainer = key;
        renderTargetButtons();
      });
      row.appendChild(chip);
    });
  }

  /* --------------------------------------------------------------- items -- */

  function filteredItems() {
    var query = state.query.trim().toLowerCase();
    if (!query) {
      return state.items;
    }
    return state.items.filter(function (item) {
      return (
        String(item.name || "").toLowerCase().indexOf(query) !== -1 ||
        String(item.className || "").toLowerCase().indexOf(query) !== -1
      );
    });
  }

  function sameItem(left, right) {
    return (
      !!left &&
      !!right &&
      left.className === right.className &&
      left.category === right.category &&
      left.entryKind === right.entryKind
    );
  }

  function renderItems() {
    var list = node("itemList");
    if (!list) {
      return;
    }
    var snapshot = scrollSnapshot();
    clear(list);

    var items = filteredItems();
    text("categoryTitle", state.categoryLabel);

    if (!items.length) {
      list.appendChild(
        el(
          "div",
          "empty",
          state.items.length
            ? "Nothing matches that search."
            : "No equipment available here.",
        ),
      );
      restoreScroll(snapshot, ["itemList"]);
      return;
    }

    items.forEach(function (item) {
      var row = el(
        "button",
        "armory-row" +
          (sameItem(item, state.selectedItem) ? " selected" : "") +
          (item.locked ? " locked" : ""),
      );
      row.type = "button";
      row.setAttribute("role", "option");
      row.setAttribute(
        "aria-selected",
        sameItem(item, state.selectedItem) ? "true" : "false",
      );
      if (item.locked && item.lockReason) {
        row.title = item.lockReason;
      }

      row.appendChild(
        renderTextureBox("card-media", item.image, categorySymbols[item.category] || ""),
      );

      var copy = el("div", "item-copy");
      copy.appendChild(el("span", "item-name", item.name));
      if (state.economyEnabled) {
        copy.appendChild(el("span", "item-price", priceLabel(itemPrice(item))));
      }
      row.appendChild(copy);

      row.addEventListener("click", function () {
        selectItem(item);
      });
      list.appendChild(row);
    });

    restoreScroll(snapshot, ["itemList"]);
  }

  function selectItem(item) {
    state.selectedItem = item;
    renderItems();
    renderDetails();
    send("store::preview", {
      className: item.className,
      category: item.category,
      entryKind: item.entryKind,
    });
  }

  function renderDetails() {
    var panel = node("itemDetails");
    if (!panel) {
      return;
    }
    clear(panel);

    var item = state.selectedItem;
    if (!item) {
      panel.appendChild(el("h2", "", ""));
      panel.appendChild(el("p", "", ""));
      panel.appendChild(el("p", "muted"));
      var emptyStatus = el("p", "", "");
      emptyStatus.id = "previewStatus";
      panel.appendChild(emptyStatus);
      return;
    }

    panel.appendChild(el("h2", "", item.name));
    panel.appendChild(el("p", "muted", item.className));

    if (state.economyEnabled) {
      panel.appendChild(el("strong", "detail-price", money(itemPrice(item))));
    }

    if (item.locked) {
      panel.appendChild(el("p", "warn", item.lockReason || "Unavailable here."));
    }

    var actions = el("div", "detail-actions");
    var attachments = includedAttachments(item);

    var add = el("button", "primary", isVehicle(item) ? "Add vehicle" : "Add to cart");
    add.type = "button";
    add.disabled = !!item.locked;
    add.addEventListener("click", function () {
      if (attachments.length) {
        showAttachmentModal(item);
        return;
      }
      addToCart(item, state.activeContainer, []);
    });
    actions.appendChild(add);

    if (attachments.length) {
      var bare = el("button", "", "Add without attachments");
      bare.type = "button";
      bare.disabled = !!item.locked;
      bare.addEventListener("click", function () {
        addToCart(item, state.activeContainer, []);
      });
      actions.appendChild(bare);
    }

    panel.appendChild(actions);

    var status = el("p", "", "");
    status.id = "previewStatus";
    panel.appendChild(status);
  }

  /* -------------------------------------------------- attachments modal -- */

  function showAttachmentModal(item) {
    var attachments = includedAttachments(item);
    state.pendingAttachmentAdd = { item: item, selected: {} };

    text("attachmentWeaponName", item.name);
    text("attachmentWeaponMeta", readable(item.category) + " · " + item.className);
    text(
      "attachmentWeaponPrice",
      state.economyEnabled ? money(itemPrice(item)) : "",
    );

    var list = node("attachmentList");
    clear(list);

    attachments.forEach(function (attachment, index) {
      var row = el("div", "attachment-row");
      var box = el("label", "");
      var check = document.createElement("input");
      check.type = "checkbox";
      check.checked = true;
      state.pendingAttachmentAdd.selected[index] = true;
      check.addEventListener("change", function () {
        state.pendingAttachmentAdd.selected[index] = check.checked;
      });
      box.appendChild(check);
      row.appendChild(box);

      row.appendChild(
        renderTextureBox("attachment-media", attachment.image, "ATT"),
      );

      var copy = el("div", "item-copy");
      copy.appendChild(el("span", "item-name", attachment.name || attachment.className));
      copy.appendChild(el("span", "attachment-slot", readable(attachment.slot || "")));
      row.appendChild(copy);

      if (state.economyEnabled) {
        row.appendChild(
          el("span", "item-price", money(Number(attachment.priceValue) || 0)),
        );
      }

      list.appendChild(row);
    });

    node("attachmentModal").classList.remove("hidden");
  }

  function hideAttachmentModal() {
    state.pendingAttachmentAdd = null;
    node("attachmentModal").classList.add("hidden");
  }

  function confirmAttachmentAdd() {
    var pending = state.pendingAttachmentAdd;
    if (!pending) {
      return;
    }
    var attachments = includedAttachments(pending.item).filter(function (_, index) {
      return pending.selected[index];
    });
    hideAttachmentModal();
    addToCart(pending.item, state.activeContainer, attachments);
  }

  /* ----------------------------------------------------------- loadouts -- */

  function renderLoadouts() {
    var list = node("loadoutList");
    if (!list) {
      return;
    }
    clear(list);

    if (!state.loadouts.length) {
      list.appendChild(
        el("div", "empty", "No saved loadouts yet. Equip what you want and save it."),
      );
      return;
    }

    state.loadouts.forEach(function (kit) {
      var row = el("div", "loadout-row");
      var copy = el("div", "name");
      copy.appendChild(el("div", "", kit.name));
      copy.appendChild(
        el("div", "meta", (kit.lineCount || 0) + " line(s)"),
      );
      row.appendChild(copy);

      var apply = el("button", "primary", "Load");
      apply.type = "button";
      apply.addEventListener("click", function () {
        send("store::loadoutApply", { id: kit.id });
      });
      row.appendChild(apply);

      var remove = el("button", "", "Delete");
      remove.type = "button";
      remove.addEventListener("click", function () {
        send("store::loadoutDelete", { id: kit.id });
      });
      row.appendChild(remove);

      list.appendChild(row);
    });
  }

  function openLoadouts() {
    node("loadoutModal").classList.remove("hidden");
    send("store::loadoutsOpen", {});
  }

  function closeLoadouts() {
    node("loadoutModal").classList.add("hidden");
  }

  /* ------------------------------------------------------------ checkout -- */

  /*  The cart is unbounded but the page->SQF channel is not. Send the cart as
      numbered chunks that each fit the cap, then a commit message. The server
      assembles by sequence and rejects an incomplete set, so a dropped chunk
      fails loudly instead of buying a silently truncated order. */
  function checkout() {
    if (state.checkoutPending || !state.cart.length) {
      return;
    }

    state.sequence += 1;
    var sequence = state.sequence;
    var chunks = [];
    var current = [];

    function chunkLength(lines) {
      return JSON.stringify({
        event: "store::cartChunk",
        data: { seq: sequence, index: 0, total: 0, items: lines },
      }).length;
    }

    var i;
    for (i = 0; i < state.cart.length; i += 1) {
      var line = {
        className: state.cart[i].className,
        entryKind: state.cart[i].entryKind,
        category: state.cart[i].category,
        container: state.cart[i].container,
        quantity: state.cart[i].quantity,
        attachments: (state.cart[i].attachments || []).map(function (entry) {
          return entry.className;
        }),
      };

      if (chunkLength([line]) > CHUNK_BUDGET) {
        message("A cart line is too large to send. Remove it and try again.", "bad");
        return;
      }

      if (current.length && chunkLength(current.concat([line])) > CHUNK_BUDGET) {
        chunks.push(current);
        current = [];
      }
      current.push(line);
    }
    if (current.length) {
      chunks.push(current);
    }

    state.checkoutPending = true;
    updateSummary();

    for (i = 0; i < chunks.length; i += 1) {
      if (
        !send("store::cartChunk", {
          seq: sequence,
          index: i,
          total: chunks.length,
          items: chunks[i],
        })
      ) {
        clearCheckoutPending();
        message("Could not send the cart. Remove some lines and try again.", "bad");
        return;
      }
    }

    send("store::checkout", { seq: sequence, total: chunks.length });

    state.checkoutTimer = window.setTimeout(function () {
      state.checkoutTimer = 0;
      if (!state.checkoutPending) {
        return;
      }
      state.checkoutPending = false;
      updateSummary();
      message("No reply from the server. Nothing was bought; try again.", "warn");
    }, CHECKOUT_TIMEOUT_MS);
  }

  function clearCheckoutPending() {
    if (state.checkoutTimer) {
      window.clearTimeout(state.checkoutTimer);
      state.checkoutTimer = 0;
    }
    state.checkoutPending = false;
    updateSummary();
  }

  /* ------------------------------------------------------------- preview -- */

  function reportViewport() {
    var viewport = node("previewViewport");
    if (!viewport) {
      return;
    }
    var rect = viewport.getBoundingClientRect();
    var width = window.innerWidth || 1;
    var height = window.innerHeight || 1;
    if (rect.width < 4 || rect.height < 4) {
      return;
    }
    send("store::previewControl", {
      action: "viewport",
      rect: [
        rect.left / width,
        rect.top / height,
        rect.width / width,
        rect.height / height,
      ],
    });
  }

  function installPreviewControls() {
    var viewport = node("previewViewport");
    if (!viewport) {
      return;
    }

    var dragging = false;
    var lastX = 0;
    var lastY = 0;
    var pendingX = 0;
    var pendingY = 0;
    var flushTimer = 0;

    function flush() {
      if (flushTimer) {
        window.clearTimeout(flushTimer);
        flushTimer = 0;
      }
      if (!pendingX && !pendingY) {
        return;
      }
      send("store::previewControl", {
        action: "orbit",
        x: pendingX,
        y: pendingY,
      });
      pendingX = 0;
      pendingY = 0;
    }

    function queueOrbit(dx, dy) {
      pendingX += dx;
      pendingY += dy;
      if (!flushTimer) {
        flushTimer = window.setTimeout(flush, 40);
      }
    }

    viewport.addEventListener("mousedown", function (event) {
      dragging = true;
      lastX = event.clientX;
      lastY = event.clientY;
      viewport.focus({ preventScroll: true });
      event.preventDefault();
    });

    window.addEventListener("mouseup", function () {
      dragging = false;
      flush();
    });

    window.addEventListener("mousemove", function (event) {
      if (!dragging) {
        return;
      }
      queueOrbit((event.clientX - lastX) * 0.4, (event.clientY - lastY) * 0.3);
      lastX = event.clientX;
      lastY = event.clientY;
    });

    viewport.addEventListener("wheel", function (event) {
      send("store::previewControl", {
        action: "zoom",
        value: event.deltaY > 0 ? 0.12 : -0.12,
      });
      event.preventDefault();
    });

    viewport.addEventListener("keydown", function (event) {
      var handled = true;
      switch (event.key) {
        case "ArrowLeft":
          queueOrbit(-8, 0);
          break;
        case "ArrowRight":
          queueOrbit(8, 0);
          break;
        case "ArrowUp":
          queueOrbit(0, -6);
          break;
        case "ArrowDown":
          queueOrbit(0, 6);
          break;
        case "+":
        case "=":
          send("store::previewControl", { action: "zoom", value: -0.12 });
          break;
        case "-":
        case "_":
          send("store::previewControl", { action: "zoom", value: 0.12 });
          break;
        default:
          handled = false;
      }
      if (handled) {
        event.preventDefault();
        flush();
      }
    });

    window.addEventListener("resize", reportViewport);
  }

  function previewMode(mode) {
    var character = node("characterMode");
    var equipment = node("equipmentMode");
    if (character) {
      character.classList.toggle("active", mode === "character");
    }
    if (equipment) {
      equipment.classList.toggle("active", mode === "equipment");
    }
    send("store::previewControl", { action: "mode", value: mode });
  }

  /* ------------------------------------------------------ inbound events -- */

  function applyResources(payload) {
    if (payload && typeof payload.balance !== "undefined") {
      state.balance = Number(payload.balance) || 0;
    }
    if (payload && typeof payload.economyEnabled !== "undefined") {
      state.economyEnabled = !!payload.economyEnabled;
    }
  }

  function hydrate(payload) {
    if (!payload || !payload.success) {
      message((payload && payload.message) || "The store is unavailable.", "bad");
      return;
    }

    applyResources(payload);
    state.categories = Array.isArray(payload.categories) ? payload.categories : [];

    var wanted = state.currentCategory;
    var present = state.categories.some(function (category) {
      return category.id === wanted && category.count;
    });
    if (!present) {
      state.currentCategory = payload.firstCategory || "";
      state.items = [];
      state.selectedItem = null;
    }

    renderCategories();
    renderTargetButtons();
    renderCart();
    updateSummary();

    if (state.currentCategory) {
      send("store::category", { category: state.currentCategory });
    } else {
      renderItems();
      renderDetails();
    }

    reportViewport();
  }

  function category(payload) {
    if (!payload || !payload.success) {
      message((payload && payload.message) || "That category is unavailable.", "bad");
      return;
    }
    applyResources(payload);
    state.currentCategory = payload.category;
    state.categoryLabel = payload.label || payload.category;
    state.items = Array.isArray(payload.items) ? payload.items : [];
    state.selectedItem = null;
    renderCategories();
    renderItems();
    renderDetails();
    updateSummary();
  }

  function checkoutResult(payload) {
    clearCheckoutPending();
    applyResources(payload);

    if (payload && payload.success) {
      state.cart = [];
      renderCart();
      message(payload.message || "Purchase complete.", "good");
    } else {
      message((payload && payload.message) || "Purchase failed.", "bad");
    }

    updateSummary();
    if (state.currentCategory) {
      send("store::category", { category: state.currentCategory });
    }
  }

  function loadouts(payload) {
    /* A denial carries a message but no list. Keep what is on screen rather
       than blanking the panel because one action failed. */
    if (payload && Array.isArray(payload.kits)) {
      state.loadouts = payload.kits;
      renderLoadouts();
    }
    if (payload && payload.message) {
      message(payload.message, payload.success ? "good" : "bad");
    }
  }

  function previewStatus(value) {
    var target = node("previewStatus");
    if (target) {
      target.textContent = String(value || "");
      target.className = value ? "warn" : "";
    }
  }

  function receive(event, payload) {
    switch (event) {
      case "hydrate":
        hydrate(payload);
        break;
      case "category":
        category(payload);
        break;
      case "checkout":
        checkoutResult(payload);
        break;
      case "loadouts":
        loadouts(payload);
        break;
      case "previewStatus":
        previewStatus(payload);
        break;
      case "message":
        message(
          (payload && payload.text) || "",
          (payload && payload.kind) || "",
        );
        break;
      default:
        break;
    }
  }

  /* ---------------------------------------------------------------- init -- */

  function bind(id, event, handler) {
    var target = node(id);
    if (target) {
      target.addEventListener(event, handler);
    }
  }

  function initialize() {
    bind("itemSearch", "input", function (event) {
      state.query = event.target.value || "";
      renderItems();
    });

    bind("cartClear", "click", function () {
      state.cart = [];
      renderCart();
      updateSummary();
    });

    bind("checkoutButton", "click", checkout);
    bind("closeButton", "click", function () {
      send("store::close", {});
    });
    bind("refreshButton", "click", function () {
      send("store::refresh", {});
    });
    bind("loadoutsButton", "click", openLoadouts);
    bind("loadoutClose", "click", closeLoadouts);
    bind("loadoutSave", "click", function () {
      var input = node("loadoutName");
      var name = input ? String(input.value || "").trim() : "";
      if (!name) {
        message("Name the loadout first.", "warn");
        return;
      }
      send("store::loadoutSave", { name: name });
      if (input) {
        input.value = "";
      }
    });

    bind("attachmentCancel", "click", hideAttachmentModal);
    bind("attachmentConfirm", "click", confirmAttachmentAdd);
    bind("previewReset", "click", function () {
      send("store::previewControl", { action: "reset" });
    });

    var modes = document.querySelectorAll("[data-preview-mode]");
    var i;
    for (i = 0; i < modes.length; i += 1) {
      (function (button) {
        button.addEventListener("click", function () {
          previewMode(button.getAttribute("data-preview-mode"));
        });
      })(modes[i]);
    }

    installPreviewControls();
    renderTargetButtons();
    renderCart();
    renderDetails();
    updateSummary();

    send("store::ready", {});
    reportViewport();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize);
  } else {
    initialize();
  }

  return {
    receive: receive,
    filter: function (value) {
      state.query = value || "";
      renderItems();
    },
  };
})();
