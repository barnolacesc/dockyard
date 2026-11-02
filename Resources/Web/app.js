// Dockyard Mobile Companion — Client Application

(function() {
  const serverToken = window.DOCKYARD_AUTH_TOKEN || '';
  const urlParams = new URLSearchParams(window.location.search);
  const rawToken = urlParams.get('token') || serverToken || localStorage.getItem('dockyard_token') || '';
  let authToken = /^[a-zA-Z0-9_]{1,64}$/.test(rawToken) ? rawToken : '';

  if (authToken) {
    localStorage.setItem('dockyard_token', authToken);
  }

  // App State
  let state = {
    connected: false,
    projects: [],
    selectedWorkstreamId: null,
    terminalLines: '',
    autoScroll: true,
    wrapMode: localStorage.getItem('dockyard_term_wrap') !== 'false',
    fontSize: parseFloat(localStorage.getItem('dockyard_term_fontsize')) || 11.5,
    isListeningVoice: false,
    speechRecognition: null,
    host: null,
    activeNewWsProjectId: null,
    modelUsage: []
  };

  // Random Name Generator for New Workstreams (Operation-Adjective-Component)
  const NAME_OPERATIONS = [
    'build', 'check', 'clean', 'clone', 'fetch', 'fixup', 'flush', 'merge',
    'parse', 'patch', 'probe', 'prune', 'pull', 'push', 'route', 'scan',
    'spawn', 'sync', 'trace', 'watch', 'debug', 'drain', 'boot', 'bind', 'fork'
  ];
  const NAME_ADJECTIVES = [
    'slow', 'fast', 'busy', 'idle', 'noisy', 'stale', 'fresh', 'clean',
    'valid', 'quick', 'sharp', 'solid', 'hot', 'warm', 'cold', 'light',
    'heavy', 'clear', 'dense', 'short', 'deep', 'smart', 'prime', 'eager', 'async'
  ];
  const NAME_COMPONENTS = [
    'core', 'gpu', 'cpu', 'ram', 'bus', 'pipe', 'proc', 'task', 'lock',
    'tcp', 'udp', 'http', 'tls', 'arp', 'byte', 'heap', 'stack', 'cache',
    'node', 'edge', 'tree', 'table', 'index', 'log', 'queue', 'chan', 'frame'
  ];

  function generateRandomWorkstreamName() {
    const op = NAME_OPERATIONS[Math.floor(Math.random() * NAME_OPERATIONS.length)];
    const adj = NAME_ADJECTIVES[Math.floor(Math.random() * NAME_ADJECTIVES.length)];
    const comp = NAME_COMPONENTS[Math.floor(Math.random() * NAME_COMPONENTS.length)];
    return `${op}-${adj}-${comp}`;
  }

  // DOM Elements
  const els = {
    connectionPill: document.getElementById('connection-pill'),
    connectionText: document.getElementById('connection-text'),
    modelUsageStrip: document.getElementById('model-usage-strip'),
    currentWsName: document.getElementById('current-ws-name'),
    currentWsBranch: document.getElementById('current-ws-branch'),
    terminalMirror: document.getElementById('terminal-mirror'),
    scrollBottomBtn: document.getElementById('scroll-bottom-btn'),
    agentWaitingBanner: document.getElementById('agent-waiting-banner'),
    waitingText: document.getElementById('waiting-text'),
    btnApprove: document.getElementById('btn-approve'),
    btnDeny: document.getElementById('btn-deny'),
    promptInput: document.getElementById('prompt-input'),
    imageInput: document.getElementById('image-input'),
    imageBtn: document.getElementById('image-btn'),
    micBtn: document.getElementById('mic-btn'),
    sendBtn: document.getElementById('send-btn'),
    sidebarOverlay: document.getElementById('sidebar-overlay'),
    sidebarDrawer: document.getElementById('sidebar-drawer'),
    drawerContent: document.getElementById('drawer-content'),
    menuBtn: document.getElementById('menu-btn'),
    drawerCloseBtn: document.getElementById('drawer-close-btn'),
    btnToggleWrap: document.getElementById('btn-toggle-wrap'),
    btnFontSize: document.getElementById('btn-font-size'),
    newWsModal: document.getElementById('new-ws-modal'),
    modalProjectName: document.getElementById('modal-project-name'),
    newWsForm: document.getElementById('new-ws-form'),
    wsNameInput: document.getElementById('ws-name-input'),
    wsDiceBtn: document.getElementById('ws-dice-btn'),
    modalDefaultsText: document.getElementById('modal-defaults-text'),
    modalCancelBtn: document.getElementById('modal-cancel-btn'),
    modalSubmitBtn: document.getElementById('modal-submit-btn'),
    modalCloseBtn: document.getElementById('modal-close-btn')
  };

  // Initialize Speech Recognition if supported
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (SpeechRecognition) {
    const recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = navigator.language || 'en-US';

    recognition.onresult = (event) => {
      let interimTranscript = '';
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        if (event.results[i].isFinal) {
          els.promptInput.value += event.results[i][0].transcript;
        } else {
          interimTranscript += event.results[i][0].transcript;
        }
      }
    };

    recognition.onend = () => {
      state.isListeningVoice = false;
      els.micBtn.classList.remove('listening');
    };

    recognition.onerror = () => {
      state.isListeningVoice = false;
      els.micBtn.classList.remove('listening');
    };

    state.speechRecognition = recognition;
  } else {
    els.micBtn.style.display = 'none';
  }

  // UI Event Handlers
  els.menuBtn.addEventListener('click', openSidebar);
  els.drawerCloseBtn.addEventListener('click', closeSidebar);
  els.sidebarOverlay.addEventListener('click', closeSidebar);

  // New Workstream Modal Event Handlers
  if (els.newWsModal) {
    els.newWsModal.addEventListener('click', (e) => {
      if (e.target === els.newWsModal) {
        closeNewWorkstreamModal();
      }
    });
  }
  if (els.modalCloseBtn) {
    els.modalCloseBtn.addEventListener('click', closeNewWorkstreamModal);
  }
  if (els.modalCancelBtn) {
    els.modalCancelBtn.addEventListener('click', closeNewWorkstreamModal);
  }
  if (els.newWsForm) {
    els.newWsForm.addEventListener('submit', handleNewWorkstreamSubmit);
  }
  if (els.wsDiceBtn) {
    els.wsDiceBtn.addEventListener('click', () => {
      if (els.wsNameInput) {
        const next = generateRandomWorkstreamName();
        els.wsNameInput.value = next;
        els.wsNameInput.focus();
        els.wsNameInput.select();
      }
    });
  }
  if (els.wsNameInput) {
    els.wsNameInput.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeNewWorkstreamModal();
      }
    });
  }

  els.btnApprove.addEventListener('click', () => sendAction('approve'));
  els.btnDeny.addEventListener('click', () => sendAction('deny'));

  els.sendBtn.addEventListener('click', sendPrompt);
  els.promptInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      sendPrompt();
    }
  });

  els.micBtn.addEventListener('click', toggleVoiceDictation);

  if (els.imageBtn && els.imageInput) {
    els.imageBtn.addEventListener('click', () => {
      els.imageInput.click();
    });

    els.imageInput.addEventListener('change', () => {
      const file = els.imageInput.files && els.imageInput.files[0];
      if (file) {
        uploadImageFile(file);
      }
    });
  }

  els.promptInput.addEventListener('paste', handlePaste);
  document.addEventListener('paste', handlePaste);

  document.querySelectorAll('.key-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const key = e.target.dataset.key;
      if (key === 'ctrl-c') {
        sendAction('interrupt');
      } else if (key === 'enter') {
        sendRawKey('\n');
      } else if (key === 'tab') {
        sendRawKey('\t');
      } else if (key === 'esc') {
        sendRawKey('\x1b');
      } else if (key === 'clear') {
        els.terminalMirror.replaceChildren();
      } else if (key === 'wrap') {
        toggleWrapMode();
      } else if (key === 'font-size') {
        cycleFontSize();
      }
    });
  });

  function updateTerminalViewMode() {
    if (state.wrapMode) {
      els.terminalMirror.classList.add('wrap-mode');
      els.terminalMirror.classList.remove('raw-mode');
      if (els.btnToggleWrap) {
        els.btnToggleWrap.textContent = 'Wrap ↩';
        els.btnToggleWrap.classList.add('active');
      }
    } else {
      els.terminalMirror.classList.remove('wrap-mode');
      els.terminalMirror.classList.add('raw-mode');
      if (els.btnToggleWrap) {
        els.btnToggleWrap.textContent = 'Scroll ⇄';
        els.btnToggleWrap.classList.remove('active');
      }
    }
    els.terminalMirror.style.fontSize = `${state.fontSize}px`;
    if (els.btnFontSize) {
      els.btnFontSize.textContent = `Aa ${state.fontSize}px`;
    }
  }

  function toggleWrapMode() {
    state.wrapMode = !state.wrapMode;
    localStorage.setItem('dockyard_term_wrap', state.wrapMode ? 'true' : 'false');
    updateTerminalViewMode();
  }

  function cycleFontSize() {
    const sizes = [10.5, 11.5, 13];
    let currentIndex = sizes.indexOf(state.fontSize);
    if (currentIndex === -1) currentIndex = 1;
    const nextIndex = (currentIndex + 1) % sizes.length;
    state.fontSize = sizes[nextIndex];
    localStorage.setItem('dockyard_term_fontsize', state.fontSize.toString());
    updateTerminalViewMode();
  }

  els.terminalMirror.addEventListener('scroll', () => {
    const threshold = 40;
    const isAtBottom = els.terminalMirror.scrollHeight - els.terminalMirror.scrollTop - els.terminalMirror.clientHeight <= threshold;
    state.autoScroll = isAtBottom;
    if (isAtBottom) {
      els.scrollBottomBtn.classList.remove('visible');
    } else {
      els.scrollBottomBtn.classList.add('visible');
    }
  });

  els.scrollBottomBtn.addEventListener('click', () => {
    scrollToBottom();
    state.autoScroll = true;
    els.scrollBottomBtn.classList.remove('visible');
  });

  function openSidebar() {
    els.sidebarDrawer.classList.add('open');
    els.sidebarOverlay.classList.add('open');
  }

  function closeSidebar() {
    els.sidebarDrawer.classList.remove('open');
    els.sidebarOverlay.classList.remove('open');
  }

  function scrollToBottom() {
    els.terminalMirror.scrollTop = els.terminalMirror.scrollHeight;
  }

  function toggleVoiceDictation() {
    if (!state.speechRecognition) return;
    if (state.isListeningVoice) {
      state.speechRecognition.stop();
      state.isListeningVoice = false;
      els.micBtn.classList.remove('listening');
    } else {
      try {
        state.speechRecognition.start();
        state.isListeningVoice = true;
        els.micBtn.classList.add('listening');
      } catch (err) {
        console.error('Speech recognition error:', err);
      }
    }
  }

  // Strict Validation Helpers
  const UUID_REGEX = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  const ALLOWED_ACTIONS = ['approve', 'deny', 'interrupt'];

  function validateWorkstreamId(id) {
    if (typeof id !== 'string' || !UUID_REGEX.test(id)) {
      throw new Error('Invalid workstream ID');
    }
    return id;
  }

  function validateProjectId(id) {
    if (typeof id !== 'string' || !UUID_REGEX.test(id)) {
      throw new Error('Invalid project ID');
    }
    return id;
  }

  function validateAction(action) {
    if (!ALLOWED_ACTIONS.includes(action)) {
      throw new Error('Invalid action');
    }
    return action;
  }

  // Network Calls with strict endpoint validation
  async function apiFetch(endpoint, options = {}) {
    if (typeof endpoint !== 'string' || !endpoint.startsWith('/api/')) {
      throw new Error('Invalid API endpoint');
    }

    const url = new URL(endpoint, window.location.origin);
    if (url.origin !== window.location.origin) {
      throw new Error('Untrusted origin');
    }

    options.headers = options.headers || {};
    if (authToken) {
      options.headers['Authorization'] = `Bearer ${authToken}`;
    }
    options.credentials = 'same-origin';

    const res = await fetch(url, options);
    if (res.status === 401) {
      setConnectionStatus(false, 'Unauthorized');
      const newToken = prompt('Enter your Dockyard Mobile token:');
      if (newToken && /^[a-zA-Z0-9_]{1,64}$/.test(newToken.trim())) {
        authToken = newToken.trim();
        localStorage.setItem('dockyard_token', authToken);
        location.reload();
      }
      throw new Error('Unauthorized');
    }
    return res;
  }

  function scheduleFastTerminalUpdates() {
    fetchCurrentTerminal();
    setTimeout(fetchCurrentTerminal, 120);
    setTimeout(fetchCurrentTerminal, 350);
    setTimeout(fetchCurrentTerminal, 700);
    setTimeout(fetchCurrentTerminal, 1200);
  }

  async function sendAction(action) {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const safeAction = validateAction(action);
      await apiFetch(`/api/workstreams/${wsId}/${safeAction}`, {
        method: 'POST'
      });
      scheduleFastTerminalUpdates();
    } catch (err) {
      console.error(`Failed to send ${action}:`, err);
    }
  }

  async function sendRawKey(key) {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      await apiFetch(`/api/workstreams/${wsId}/input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: key, pressEnter: false })
      });
      scheduleFastTerminalUpdates();
    } catch (err) {
      console.error('Failed to send key:', err);
    }
  }

  async function sendPrompt() {
    const text = els.promptInput.value.trim();
    if (!text || !state.selectedWorkstreamId) return;
    els.promptInput.value = '';
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      await apiFetch(`/api/workstreams/${wsId}/input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: text, pressEnter: true })
      });
      scheduleFastTerminalUpdates();
    } catch (err) {
      console.error('Failed to send prompt:', err);
    }
  }

  function handlePaste(e) {
    if (e.defaultPrevented) return;
    const items = (e.clipboardData || e.originalEvent?.clipboardData)?.items;
    if (!items) return;

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.type && item.type.startsWith('image/')) {
        const file = item.getAsFile();
        if (file) {
          e.preventDefault();
          uploadImageFile(file);
          return;
        }
      }
    }
  }

  async function downscaleImageIfNeeded(file) {
    if (!file || !file.type || !file.type.startsWith('image/')) {
      return { blob: file, type: file?.type || 'image/png' };
    }

    return new Promise((resolve) => {
      const img = new Image();
      const objectUrl = URL.createObjectURL(file);

      img.onload = () => {
        URL.revokeObjectURL(objectUrl);
        const MAX_DIM = 2048;
        let { width, height } = img;

        if (width <= MAX_DIM && height <= MAX_DIM) {
          resolve({ blob: file, type: file.type || 'image/png' });
          return;
        }

        if (width > height) {
          height = Math.round((height * MAX_DIM) / width);
          width = MAX_DIM;
        } else {
          width = Math.round((width * MAX_DIM) / height);
          height = MAX_DIM;
        }

        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
          resolve({ blob: file, type: file.type || 'image/png' });
          return;
        }
        ctx.drawImage(img, 0, 0, width, height);

        const mime = (file.type === 'image/jpeg' || file.type === 'image/webp') ? file.type : 'image/png';
        canvas.toBlob((blob) => {
          if (blob) {
            resolve({ blob, type: mime });
          } else {
            resolve({ blob: file, type: file.type || 'image/png' });
          }
        }, mime, 0.85);
      };

      img.onerror = () => {
        URL.revokeObjectURL(objectUrl);
        resolve({ blob: file, type: file.type || 'image/png' });
      };

      img.src = objectUrl;
    });
  }

  function setUploadingImage(uploading) {
    if (!els.imageBtn) return;
    if (uploading) {
      els.imageBtn.classList.add('uploading');
      els.imageBtn.setAttribute('aria-label', 'Uploading...');
      els.imageBtn.setAttribute('title', 'Uploading...');
      els.imageBtn.disabled = true;
    } else {
      els.imageBtn.classList.remove('uploading');
      els.imageBtn.setAttribute('aria-label', 'Upload image');
      els.imageBtn.setAttribute('title', 'Upload image');
      els.imageBtn.disabled = false;
    }
  }

  function insertPathIntoPrompt(filePath) {
    const input = els.promptInput;
    if (!input) return;

    const val = input.value;
    const start = input.selectionStart;
    const end = input.selectionEnd;

    let prefix = '';
    let suffix = ' ';

    if (typeof start === 'number' && typeof end === 'number') {
      const before = val.substring(0, start);
      const after = val.substring(end);
      if (before.length > 0 && !before.endsWith(' ')) {
        prefix = ' ';
      }
      if (after.length > 0 && after.startsWith(' ')) {
        suffix = '';
      }
      const inserted = prefix + filePath + suffix;
      input.value = before + inserted + after;
      const newCursorPos = before.length + inserted.length;
      input.setSelectionRange(newCursorPos, newCursorPos);
    } else {
      if (val.length > 0 && !val.endsWith(' ')) {
        prefix = ' ';
      }
      input.value = val + prefix + filePath + suffix;
    }

    input.focus();
  }

  async function uploadImageFile(file) {
    if (!state.selectedWorkstreamId) {
      alert('Please select a workstream first.');
      return;
    }
    if (!file || !file.type || !file.type.startsWith('image/')) {
      return;
    }

    setUploadingImage(true);
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const { blob, type } = await downscaleImageIfNeeded(file);

      const res = await apiFetch(`/api/workstreams/${wsId}/image`, {
        method: 'POST',
        headers: {
          'Content-Type': type
        },
        body: blob
      });

      if (!res.ok) {
        throw new Error(`Upload failed with status: ${res.status}`);
      }

      const json = await res.json();
      if (json.ok && json.path) {
        insertPathIntoPrompt(json.path);
      } else {
        throw new Error(json.error || 'Failed to upload image');
      }
    } catch (err) {
      console.error('Failed to upload image:', err);
      alert('Failed to upload image');
    } finally {
      setUploadingImage(false);
      if (els.imageInput) {
        els.imageInput.value = '';
      }
    }
  }

  async function fetchInitialStatus() {
    try {
      const res = await apiFetch('/api/status');
      const data = await res.json();
      state.projects = data.projects || [];
      state.host = data.host || null;
      if (data.modelUsage) {
        state.modelUsage = data.modelUsage;
        renderModelUsage();
      }
      renderSidebar();

      // Pick first workstream if none selected
      if (!state.selectedWorkstreamId) {
        for (const proj of state.projects) {
          if (proj.workstreams && proj.workstreams.length > 0) {
            selectWorkstream(proj.workstreams[0].id);
            break;
          }
        }
      } else {
        updateCurrentWorkstreamHeader();
      }
      setConnectionStatus(true, data.host?.name || 'Connected');
    } catch (err) {
      console.error('Failed to fetch status:', err);
      setConnectionStatus(false, 'Disconnected');
    }
  }

  let isFetchingTerminal = false;
  async function fetchCurrentTerminal() {
    if (!state.selectedWorkstreamId || isFetchingTerminal) return;
    if (document.visibilityState !== 'visible') return;
    isFetchingTerminal = true;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const res = await apiFetch(`/api/workstreams/${wsId}/terminal?lines=150`);
      if (res.ok) {
        const text = await res.text();
        renderTerminal(text);
      }
    } catch (err) {
      console.error('Failed to fetch terminal:', err);
    } finally {
      isFetchingTerminal = false;
    }
  }

  let isFetchingStatus = false;
  async function fetchStatusSilently() {
    if (isFetchingStatus) return;
    if (document.visibilityState !== 'visible') return;
    isFetchingStatus = true;
    try {
      const res = await apiFetch('/api/status');
      if (res.ok) {
        const data = await res.json();
        state.projects = data.projects || [];
        renderSidebar();
        updateCurrentWorkstreamHeader();
      }
    } catch (err) {
      console.error('Failed to fetch status silently:', err);
    } finally {
      isFetchingStatus = false;
    }
  }

  function setConnectionStatus(connected, text) {
    state.connected = connected;
    if (connected) {
      els.connectionPill.classList.add('connected');
    } else {
      els.connectionPill.classList.remove('connected');
    }
    els.connectionText.textContent = text;
  }

  function selectWorkstream(id) {
    if (!id || typeof id !== 'string' || !/^[0-9a-fA-F-]{1,64}$/.test(id)) return;
    const found = findWorkstream(id);
    if (!found) return;
    state.selectedWorkstreamId = found.workstream.id;
    closeSidebar();
    updateCurrentWorkstreamHeader();
    renderSidebar();
    fetchCurrentTerminal();
  }

  function findWorkstream(id) {
    for (const p of state.projects) {
      for (const w of (p.workstreams || [])) {
        if (w.id === id) return { project: p, workstream: w };
      }
    }
    return null;
  }

  function updateCurrentWorkstreamHeader() {
    const found = findWorkstream(state.selectedWorkstreamId);
    if (found) {
      els.currentWsName.textContent = found.workstream.name;
      els.currentWsBranch.textContent = found.workstream.branch || found.project.name;

      if (found.workstream.agentState === 'waiting') {
        els.agentWaitingBanner.style.display = 'flex';
        els.waitingText.textContent = 'Agent is waiting for input or approval';
      } else {
        els.agentWaitingBanner.style.display = 'none';
      }
    } else {
      els.currentWsName.textContent = 'Dockyard';
      els.currentWsBranch.textContent = 'No workstream selected';
      els.agentWaitingBanner.style.display = 'none';
    }
  }

  // Model Usage in Header (Top Right)
  const PROVIDER_ICONS = {
    agy: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M 19.08 19.44C 20.05 20.17 21.50 19.68 20.17 18.35C 16.18 14.48 17.02 3.83 12.06 3.83C 7.10 3.83 7.95 14.48 3.95 18.35C 2.50 19.81 4.07 20.17 5.04 19.44C 8.79 16.90 8.55 12.42 12.06 12.42C 15.57 12.42 15.33 16.90 19.08 19.44Z"/></svg>',
    gemini: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M 19.08 19.44C 20.05 20.17 21.50 19.68 20.17 18.35C 16.18 14.48 17.02 3.83 12.06 3.83C 7.10 3.83 7.95 14.48 3.95 18.35C 2.50 19.81 4.07 20.17 5.04 19.44C 8.79 16.90 8.55 12.42 12.06 12.42C 15.57 12.42 15.33 16.90 19.08 19.44Z"/></svg>',
    codex: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"/></svg>',
    openai: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"/></svg>',
    claude: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/></svg>'
  };

  function remainingHealthClass(val) {
    if (val === null || val === undefined) return '';
    if (val <= 10) return 'danger';
    if (val <= 20) return 'warning';
    return 'healthy';
  }

  function formatResetTime(isoStr) {
    if (!isoStr) return '';
    try {
      const d = new Date(isoStr);
      if (isNaN(d.getTime())) return isoStr;
      return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + ' ' + d.toLocaleDateString([], { weekday: 'short' });
    } catch (e) {
      return isoStr;
    }
  }

  function showToast(text) {
    let toast = document.getElementById('usage-toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'usage-toast';
      toast.className = 'usage-toast';
      document.body.appendChild(toast);
    }
    toast.textContent = text;
    toast.classList.add('visible');
    clearTimeout(toast._timeout);
    toast._timeout = setTimeout(() => {
      toast.classList.remove('visible');
    }, 3200);
  }

  async function triggerUsageRefresh() {
    showToast('Refreshing model limits...');
    try {
      await apiFetch('/api/usage/refresh', { method: 'POST' });
    } catch (e) {
      // Ignore network errors
    }
  }

  function renderModelUsage() {
    if (!els.modelUsageStrip) return;
    els.modelUsageStrip.replaceChildren();

    const usageList = state.modelUsage || [];
    if (!usageList.length) {
      els.modelUsageStrip.style.display = 'none';
      return;
    }

    els.modelUsageStrip.style.display = 'flex';

    for (const item of usageList) {
      const providerKey = (item.provider || '').toLowerCase();
      const svgIcon = PROVIDER_ICONS[providerKey] || PROVIDER_ICONS.agy;

      const pill = document.createElement('div');
      pill.className = 'model-usage-pill';
      pill.setAttribute('data-provider', providerKey);

      const fiveHourText = (item.fiveHourRemaining !== undefined && item.fiveHourRemaining !== null)
        ? `${item.fiveHourRemaining}%`
        : '--';
      const weeklyText = (item.weeklyRemaining !== undefined && item.weeklyRemaining !== null)
        ? `${item.weeklyRemaining}%`
        : '--';

      const tooltip = `${item.name || providerKey}: ${fiveHourText} remaining (5h) • ${weeklyText} remaining (weekly)`;
      pill.title = tooltip;

      const iconSpan = document.createElement('span');
      iconSpan.className = `model-usage-icon ${providerKey}`;
      iconSpan.innerHTML = svgIcon;
      pill.appendChild(iconSpan);

      const numbersDiv = document.createElement('div');
      numbersDiv.className = 'model-usage-numbers';

      const hSpan = document.createElement('span');
      hSpan.className = `model-usage-val ${remainingHealthClass(item.fiveHourRemaining)}`;
      hSpan.textContent = fiveHourText;
      hSpan.title = '5-hour limit remaining';

      const wSpan = document.createElement('span');
      wSpan.className = `model-usage-val ${remainingHealthClass(item.weeklyRemaining)}`;
      wSpan.textContent = weeklyText;
      wSpan.title = 'Weekly limit remaining';

      numbersDiv.appendChild(hSpan);
      numbersDiv.appendChild(wSpan);
      pill.appendChild(numbersDiv);

      pill.addEventListener('click', (e) => {
        e.stopPropagation();
        let details = `${item.name || providerKey}\n5h: ${fiveHourText} remaining\nWeekly: ${weeklyText} remaining`;
        if (item.resetsAt5h) {
          details += `\n5h resets: ${formatResetTime(item.resetsAt5h)}`;
        }
        if (item.resetsAtWeekly) {
          details += `\nWeekly resets: ${formatResetTime(item.resetsAtWeekly)}`;
        }
        showToast(details);
        triggerUsageRefresh();
      });

      els.modelUsageStrip.appendChild(pill);
    }
  }

  function updateModalDefaultsText() {
    const agentMap = {
      claude: 'Claude Code',
      codex: 'Codex',
      agy: 'Antigravity CLI (AGY)',
      opencode: 'OpenCode',
      pi: 'Pi'
    };
    const host = state.host || {};
    const agentName = agentMap[host.defaultAgent] || (host.defaultAgent ? host.defaultAgent : 'Default agent');
    const bypassText = host.defaultBypass ? 'YOLO permissions' : 'Default permissions';
    if (els.modalDefaultsText) {
      els.modalDefaultsText.textContent = `${agentName} • ${bypassText}`;
    }
  }

  function openNewWorkstreamModal(proj) {
    if (!proj) return;
    state.activeNewWsProjectId = proj.id;
    if (els.modalProjectName) {
      els.modalProjectName.textContent = proj.name || 'Untitled Project';
    }
    const suggested = generateRandomWorkstreamName();
    if (els.wsNameInput) {
      els.wsNameInput.value = suggested;
      els.wsNameInput.placeholder = suggested;
    }
    updateModalDefaultsText();
    if (els.newWsModal) {
      els.newWsModal.style.display = 'flex';
      setTimeout(() => {
        if (els.wsNameInput) {
          els.wsNameInput.focus();
          els.wsNameInput.select();
        }
      }, 50);
    }
  }

  function closeNewWorkstreamModal() {
    state.activeNewWsProjectId = null;
    if (els.newWsModal) {
      els.newWsModal.style.display = 'none';
    }
    if (els.modalSubmitBtn) {
      els.modalSubmitBtn.disabled = false;
      els.modalSubmitBtn.textContent = 'Create';
    }
  }

  async function handleNewWorkstreamSubmit(e) {
    if (e) e.preventDefault();
    if (!state.activeNewWsProjectId) return;
    if (els.modalSubmitBtn && els.modalSubmitBtn.disabled) return;

    const requestedName = (els.wsNameInput ? els.wsNameInput.value : '').trim();
    if (els.modalSubmitBtn) {
      els.modalSubmitBtn.disabled = true;
      els.modalSubmitBtn.textContent = 'Creating...';
    }

    try {
      const projId = validateProjectId(state.activeNewWsProjectId);
      const res = await apiFetch(`/api/projects/${projId}/workstreams`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestedName ? { name: requestedName } : {})
      });
      const data = await res.json();
      if (data.ok && data.workstream) {
        let found = findWorkstream(data.workstream.id);
        const proj = state.projects.find(p => p.id === state.activeNewWsProjectId);
        if (!found && proj) {
          if (!proj.workstreams) proj.workstreams = [];
          proj.workstreams.push({
            id: data.workstream.id,
            name: data.workstream.name,
            branch: data.workstream.branch,
            agentState: 'idle',
            activeSubagents: 0,
            listeningPorts: []
          });
        }
        closeNewWorkstreamModal();
        closeSidebar();
        selectWorkstream(data.workstream.id);
      } else {
        alert(data.error || 'Failed to create workstream');
        if (els.modalSubmitBtn) {
          els.modalSubmitBtn.disabled = false;
          els.modalSubmitBtn.textContent = 'Create';
        }
      }
    } catch (err) {
      console.error('Failed to create workstream:', err);
      alert('Failed to create workstream: ' + (err.message || 'Network error'));
      if (els.modalSubmitBtn) {
        els.modalSubmitBtn.disabled = false;
        els.modalSubmitBtn.textContent = 'Create';
      }
    }
  }

  function renderSidebar() {
    els.drawerContent.replaceChildren();

    if (!state.projects || state.projects.length === 0) {
      const emptyMsg = document.createElement('div');
      emptyMsg.className = 'empty-projects-msg';
      emptyMsg.textContent = 'No active projects found';
      els.drawerContent.appendChild(emptyMsg);
      return;
    }

    for (const proj of state.projects) {
      const groupEl = document.createElement('div');
      groupEl.className = 'project-group';

      const headerEl = document.createElement('div');
      headerEl.className = 'project-header';

      const titleEl = document.createElement('div');
      titleEl.className = 'project-title';
      titleEl.textContent = proj.name || 'Untitled';
      headerEl.appendChild(titleEl);

      const addBtn = document.createElement('button');
      addBtn.className = 'add-ws-btn';
      addBtn.title = 'New Workstream';
      addBtn.setAttribute('aria-label', 'New Workstream');
      addBtn.textContent = '+';

      addBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        openNewWorkstreamModal(proj);
      });

      headerEl.appendChild(addBtn);
      groupEl.appendChild(headerEl);

      for (const ws of (proj.workstreams || [])) {
        const isSelected = ws.id === state.selectedWorkstreamId;
        const stateClass = ws.agentState || 'idle';
        let stateLabel = stateClass.toUpperCase();
        if (ws.agentState === 'working') stateLabel = 'WORKING';
        if (ws.agentState === 'waiting') stateLabel = 'WAITING';

        const card = document.createElement('div');
        card.className = `workstream-card ${isSelected ? 'selected' : ''}`;
        card.dataset.id = ws.id;

        const rowTop = document.createElement('div');
        rowTop.className = 'ws-row-top';

        const nameSpan = document.createElement('span');
        nameSpan.className = 'ws-name';
        nameSpan.textContent = ws.name || 'Unnamed';

        const actionsWrapper = document.createElement('div');
        actionsWrapper.className = 'ws-actions';

        const badge = document.createElement('span');
        badge.className = `ws-badge ${stateClass}`;

        const dot = document.createElement('span');
        dot.className = 'dot';
        badge.appendChild(dot);
        badge.appendChild(document.createTextNode(' ' + stateLabel));
        actionsWrapper.appendChild(badge);

        const closeBtn = document.createElement('button');
        closeBtn.className = 'close-ws-btn';
        closeBtn.title = 'Archive';
        closeBtn.setAttribute('aria-label', 'Archive');
        closeBtn.textContent = '✕';
        closeBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const confirmed = window.confirm(`Archive workstream ${ws.name}? Files will remain on disk.`);
          if (!confirmed) return;

          try {
            const wsId = validateWorkstreamId(ws.id);
            await apiFetch(`/api/workstreams/${wsId}/close`, {
              method: 'POST'
            });

            if (proj.workstreams) {
              proj.workstreams = proj.workstreams.filter(w => w.id !== ws.id);
            }

            if (state.selectedWorkstreamId === ws.id) {
              let nextWs = null;
              for (const p of state.projects) {
                for (const w of (p.workstreams || [])) {
                  if (w.id !== ws.id) {
                    nextWs = w;
                    break;
                  }
                }
                if (nextWs) break;
              }
              if (nextWs) {
                selectWorkstream(nextWs.id);
              } else {
                state.selectedWorkstreamId = null;
                updateCurrentWorkstreamHeader();
                renderSidebar();
                els.terminalMirror.replaceChildren();
              }
            } else {
              renderSidebar();
            }
          } catch (err) {
            console.error('Failed to archive workstream:', err);
          }
        });
        actionsWrapper.appendChild(closeBtn);

        rowTop.appendChild(nameSpan);
        rowTop.appendChild(actionsWrapper);
        card.appendChild(rowTop);

        const branchEl = document.createElement('div');
        branchEl.className = 'ws-branch';
        branchEl.textContent = ws.branch || '';
        card.appendChild(branchEl);

        const tagsEl = document.createElement('div');
        tagsEl.className = 'ws-tags';

        if (ws.activeSubagents > 0) {
          const subtag = document.createElement('span');
          subtag.className = 'ws-tag';
          subtag.textContent = `${ws.activeSubagents} Subagent${ws.activeSubagents > 1 ? 's' : ''}`;
          tagsEl.appendChild(subtag);
        }

        if (Array.isArray(ws.listeningPorts)) {
          for (const port of ws.listeningPorts) {
            const portNum = parseInt(port, 10);
            if (portNum > 0 && portNum <= 65535) {
              const portLink = document.createElement('a');
              portLink.className = 'ws-tag port';
              portLink.target = '_blank';
              portLink.rel = 'noopener noreferrer';
              portLink.textContent = `Port ${portNum} ↗`;
              portLink.href = `http://${window.location.hostname}:${portNum}`;
              portLink.addEventListener('click', (e) => e.stopPropagation());
              tagsEl.appendChild(portLink);
            }
          }
        }

        card.appendChild(tagsEl);

        card.addEventListener('click', () => {
          selectWorkstream(ws.id);
        });

        groupEl.appendChild(card);
      }

      els.drawerContent.appendChild(groupEl);
    }
  }

  function xterm256Color(n) {
    if (n < 16) {
      const std = ['#000', '#c00', '#0c0', '#c60', '#00c', '#c0c', '#0cc', '#ccc', '#666', '#f33', '#3f3', '#ff3', '#33f', '#f3f', '#3ff', '#fff'];
      return std[n] || '#fff';
    }
    if (n >= 232) {
      const g = 8 + (n - 232) * 10;
      return `rgb(${g},${g},${g})`;
    }
    n -= 16;
    const r = Math.floor(n / 36) * 51;
    const g = Math.floor((n % 36) / 6) * 51;
    const b = (n % 6) * 51;
    return `rgb(${r},${g},${b})`;
  }

  const ANSI_CODE_TO_CLASS = {
    1: 'ansi-bold', 2: 'ansi-dim', 3: 'ansi-italic', 4: 'ansi-underline',
    30: 'ansi-black', 31: 'ansi-red', 32: 'ansi-green', 33: 'ansi-yellow',
    34: 'ansi-blue', 35: 'ansi-magenta', 36: 'ansi-cyan', 37: 'ansi-white',
    40: 'ansi-bg-black', 41: 'ansi-bg-red', 42: 'ansi-bg-green', 43: 'ansi-bg-yellow',
    44: 'ansi-bg-blue', 45: 'ansi-bg-magenta', 46: 'ansi-bg-cyan', 47: 'ansi-bg-white',
    90: 'ansi-bright-black', 91: 'ansi-bright-red', 92: 'ansi-bright-green', 93: 'ansi-bright-yellow',
    94: 'ansi-bright-blue', 95: 'ansi-bright-magenta', 96: 'ansi-bright-cyan', 97: 'ansi-bright-white',
    100: 'ansi-bg-bright-black', 101: 'ansi-bg-bright-red', 102: 'ansi-bg-bright-green', 103: 'ansi-bg-bright-yellow',
    104: 'ansi-bg-bright-blue', 105: 'ansi-bg-bright-magenta', 106: 'ansi-bg-bright-cyan', 107: 'ansi-bg-bright-white'
  };

  function parseAnsiTokens(str) {
    let result = '';
    let currentClasses = new Set();
    let currentFgStyle = '';
    let currentBgStyle = '';

    const tokens = str.split(/(\x1b\[[0-9;]*m)/g);

    for (const token of tokens) {
      if (token.startsWith('\x1b[')) {
        const rawCodes = token.slice(2, -1).split(';').map(n => parseInt(n, 10) || 0);
        let i = 0;
        while (i < rawCodes.length) {
          const code = rawCodes[i];
          if (code === 0) {
            currentClasses.clear();
            currentFgStyle = '';
            currentBgStyle = '';
            i++;
          } else if (code === 38 && rawCodes[i + 1] === 2 && i + 4 < rawCodes.length) {
            currentFgStyle = `color: rgb(${rawCodes[i + 2]}, ${rawCodes[i + 3]}, ${rawCodes[i + 4]});`;
            i += 5;
          } else if (code === 48 && rawCodes[i + 1] === 2 && i + 4 < rawCodes.length) {
            currentBgStyle = `background-color: rgb(${rawCodes[i + 2]}, ${rawCodes[i + 3]}, ${rawCodes[i + 4]});`;
            i += 5;
          } else if (code === 38 && rawCodes[i + 1] === 5 && i + 2 < rawCodes.length) {
            currentFgStyle = `color: ${xterm256Color(rawCodes[i + 2])};`;
            i += 3;
          } else if (code === 48 && rawCodes[i + 1] === 5 && i + 2 < rawCodes.length) {
            currentBgStyle = `background-color: ${xterm256Color(rawCodes[i + 2])};`;
            i += 3;
          } else if (ANSI_CODE_TO_CLASS[code]) {
            currentClasses.add(ANSI_CODE_TO_CLASS[code]);
            i++;
          } else {
            i++;
          }
        }
      } else if (token) {
        const classAttr = currentClasses.size > 0 ? ` class="${Array.from(currentClasses).join(' ')}"` : '';
        const styleStr = (currentFgStyle + ' ' + currentBgStyle).trim();
        const styleAttr = styleStr ? ` style="${styleStr}"` : '';
        if (classAttr || styleAttr) {
          result += `<span${classAttr}${styleAttr}>${escapeHtml(token)}</span>`;
        } else {
          result += escapeHtml(token);
        }
      }
    }
    return result;
  }

  function isArtLine(line, plain) {
    // Unicode blocks, box drawing, braille, geometric shapes
    const graphicCount = (plain.match(/[\u2580-\u259F\u2500-\u257F\u2800-\u28FF\u25A0-\u25FF]/g) || []).length;
    if (graphicCount >= 2) return true;

    // Background color sequences on lines with visible content (colored banner bars)
    const hasBg = /\x1b\[(?:4[0-7]|10[0-7]|48[;0-9]*)m/.test(line);
    if (hasBg && plain.length >= 6) return true;

    // Classic ASCII art patterns (slashes, pipes, underscores, hashes)
    const asciiArtChars = (plain.match(/[/\\|_#`~^]/g) || []).length;
    if (asciiArtChars >= 6 && asciiArtChars / (plain.length || 1) >= 0.3) return true;

    return false;
  }

  // Raw ANSI to HTML Parser with divider clipping, ASCII art preservation, and trailing space trim
  function ansiToHtml(str) {
    if (!str) return '';

    str = str.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    str = str.replace(/\x1b\[\?25[hl]/g, '');
    str = str.replace(/\x1b\[[0-9;]*[HfABCDsuJK]/g, '');

    const rawLines = str.split('\n');

    // Trim excessive trailing empty lines from tmux capture
    while (rawLines.length > 0 && rawLines[rawLines.length - 1].replace(/\x1b\[[0-9;]*m/g, '').trim() === '') {
      rawLines.pop();
    }

    if (rawLines.length === 0) return '';

    let html = '';
    let currentArtLines = [];

    function flushArt() {
      if (currentArtLines.length > 0) {
        html += `<div class="term-art-block">${currentArtLines.join('')}</div>`;
        currentArtLines = [];
      }
    }

    for (const line of rawLines) {
      const plain = line.replace(/\x1b\[[0-9;]*m/g, '').trim();
      const isSeparator = /^([─━═_\-—┄┈=])\1{7,}$/.test(plain) ||
                          /^[\s─━═_\-—┄┈=]{12,}$/.test(plain) ||
                          /^[┌├└][─━═_\-—┄┈=]{8,}[┐┤┘]?$/.test(plain);

      if (isSeparator) {
        flushArt();
        const parsed = parseAnsiTokens(line);
        const content = parsed.length > 0 ? parsed : '&nbsp;';
        html += `<div class="term-line term-divider">${content}</div>`;
      } else if (isArtLine(line, plain)) {
        const parsed = parseAnsiTokens(line);
        const content = parsed.length > 0 ? parsed : '&nbsp;';
        currentArtLines.push(`<div class="term-line term-art">${content}</div>`);
      } else {
        flushArt();
        const parsed = parseAnsiTokens(line);
        const content = parsed.length > 0 ? parsed : '&nbsp;';
        html += `<div class="term-line">${content}</div>`;
      }
    }
    flushArt();

    return html;
  }

  function renderTerminal(text) {
    els.terminalMirror.innerHTML = ansiToHtml(text);
    if (state.autoScroll) {
      scrollToBottom();
    }
  }

  function escapeHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // WebSocket Connection
  function setupWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws?token=${encodeURIComponent(authToken)}`;

    let ws = null;
    let pingTimer = null;
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      setTimeout(setupWebSocket, 1500);
      return;
    }

    ws.onopen = () => {
      setConnectionStatus(true, 'Live');
      pingTimer = setInterval(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send('ping');
        }
      }, 8000);
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'snapshot') {
          state.projects = msg.projects || [];
          if (msg.host) state.host = msg.host;
          if (msg.modelUsage) {
            state.modelUsage = msg.modelUsage;
            renderModelUsage();
          }
          if (state.selectedWorkstreamId && !findWorkstream(state.selectedWorkstreamId)) {
            let nextWs = null;
            for (const p of state.projects) {
              for (const w of (p.workstreams || [])) {
                nextWs = w;
                break;
              }
              if (nextWs) break;
            }
            if (nextWs) {
              selectWorkstream(nextWs.id);
            } else {
              state.selectedWorkstreamId = null;
              els.terminalMirror.replaceChildren();
            }
          }
          renderSidebar();
          updateCurrentWorkstreamHeader();
        } else if (msg.type === 'state_change') {
          for (const proj of state.projects) {
            for (const ws of (proj.workstreams || [])) {
              if (ws.id === msg.workstreamId) {
                ws.agentState = msg.state;
                if (msg.subagents !== undefined) ws.activeSubagents = msg.subagents;
              }
            }
          }
          renderSidebar();
          updateCurrentWorkstreamHeader();
        } else if (msg.type === 'terminal_chunk') {
          if (msg.workstreamId === state.selectedWorkstreamId && msg.text) {
            renderTerminal(msg.text);
          }
        }
      } catch (err) {
        console.error('Error handling WebSocket message:', err);
      }
    };

    ws.onclose = () => {
      if (pingTimer) clearInterval(pingTimer);
      setConnectionStatus(false, 'Reconnecting...');
      setTimeout(setupWebSocket, 1500);
    };

    ws.onerror = () => {
      if (pingTimer) clearInterval(pingTimer);
      ws.close();
    };
  }

  // Fast 850ms terminal polling for real-time responsiveness
  setInterval(() => {
    if (document.visibilityState === 'visible' && state.selectedWorkstreamId) {
      fetchCurrentTerminal();
    }
  }, 850);

  // Fast 1500ms status refresh to keep workstreams and agent badges live
  setInterval(() => {
    if (document.visibilityState === 'visible') {
      fetchStatusSilently();
    }
  }, 1500);

  // Instant refresh when unlocking phone or switching back to app
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      fetchStatusSilently();
      fetchCurrentTerminal();
    }
  });
  window.addEventListener('focus', () => {
    fetchStatusSilently();
    fetchCurrentTerminal();
  });

  // Initial load
  updateTerminalViewMode();
  fetchInitialStatus().then(() => {
    setupWebSocket();
    fetchCurrentTerminal();
  });
})();
