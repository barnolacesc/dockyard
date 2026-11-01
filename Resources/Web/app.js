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
    activeNewWsProjectId: null
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

  async function sendAction(action) {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const safeAction = validateAction(action);
      await apiFetch(`/api/workstreams/${wsId}/${safeAction}`, {
        method: 'POST'
      });
      // Refresh terminal after short delay
      setTimeout(fetchCurrentTerminal, 300);
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
      setTimeout(fetchCurrentTerminal, 250);
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
      setTimeout(fetchCurrentTerminal, 350);
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

  async function fetchCurrentTerminal() {
    if (!state.selectedWorkstreamId) return;
    try {
      const wsId = validateWorkstreamId(state.selectedWorkstreamId);
      const res = await apiFetch(`/api/workstreams/${wsId}/terminal?lines=150`);
      if (res.ok) {
        const text = await res.text();
        renderTerminal(text);
      }
    } catch (err) {
      console.error('Failed to fetch terminal:', err);
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
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      setTimeout(setupWebSocket, 3000);
      return;
    }

    ws.onopen = () => {
      setConnectionStatus(true, 'Live');
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'snapshot') {
          state.projects = msg.projects || [];
          if (msg.host) state.host = msg.host;
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
      setConnectionStatus(false, 'Reconnecting...');
      setTimeout(setupWebSocket, 3000);
    };

    ws.onerror = () => {
      ws.close();
    };
  }

  // Polling fallback to keep terminal fresh even without WebSocket updates
  setInterval(() => {
    if (document.visibilityState === 'visible' && state.selectedWorkstreamId) {
      fetchCurrentTerminal();
    }
  }, 2500);

  // Initial load
  updateTerminalViewMode();
  fetchInitialStatus().then(() => {
    setupWebSocket();
    fetchCurrentTerminal();
  });
})();
