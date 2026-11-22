export const ADMIN_DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>SecretPlay — پنل فرماندهی و مدیریت کلودفلر</title>
  <style>
    :root {
      --bg: #08090f;
      --card: #121420;
      --border: #23283e;
      --neon-green: #00ffa3;
      --neon-cyan: #00e5ff;
      --neon-pink: #ff007a;
      --neon-amber: #ffb800;
      --neon-red: #ff3b30;
      --text: #f1f5f9;
      --muted: #94a3b8;
    }
    * { box-sizing: border-box; font-family: system-ui, -apple-system, 'Segoe UI', Tahoma, sans-serif; }
    body {
      margin: 0;
      background: radial-gradient(circle at top right, #13182e 0%, var(--bg) 60%);
      color: var(--text);
      min-height: 100vh;
      padding: 20px;
    }
    .container { max-width: 1240px; margin: 0 auto; }
    header {
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      padding: 18px 24px;
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 18px;
      margin-bottom: 22px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    }
    .brand { display: flex; align-items: center; gap: 14px; }
    .brand-badge {
      width: 44px; height: 44px;
      border-radius: 12px;
      background: linear-gradient(135deg, var(--neon-green), var(--neon-cyan));
      color: #000;
      display: flex; align-items: center; justify-content: center;
      font-weight: 900; font-size: 20px;
    }
    .brand h1 { margin: 0; font-size: 19px; color: #fff; }
    .brand p { margin: 3px 0 0; font-size: 12px; color: var(--muted); }
    .auth-bar { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    input, select {
      background: #0b0d16;
      border: 1px solid var(--border);
      color: #fff;
      padding: 10px 14px;
      border-radius: 10px;
      font-size: 13px;
    }
    button {
      cursor: pointer;
      border: none;
      padding: 10px 16px;
      border-radius: 10px;
      font-weight: 700;
      font-size: 12px;
      transition: all 0.15s ease;
    }
    button:hover { transform: translateY(-1px); filter: brightness(1.1); }
    .btn-green { background: var(--neon-green); color: #000; }
    .btn-cyan { background: var(--neon-cyan); color: #000; }
    .btn-pink { background: var(--neon-pink); color: #fff; }
    .btn-red { background: var(--neon-red); color: #fff; }
    .btn-amber { background: var(--neon-amber); color: #000; }
    .btn-ghost { background: #1d2136; color: #cbd5e1; border: 1px solid var(--border); }

    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(185px, 1fr));
      gap: 14px;
      margin-bottom: 22px;
    }
    .stat-card {
      background: var(--card);
      border: 1px solid var(--border);
      padding: 18px;
      border-radius: 16px;
      position: relative;
      overflow: hidden;
    }
    .stat-card h3 { margin: 0; font-size: 12px; color: var(--muted); font-weight: 600; }
    .stat-card .val { margin-top: 8px; font-size: 28px; font-weight: 800; color: #fff; font-family: monospace; }
    .stat-card .sub { margin-top: 4px; font-size: 11px; color: var(--neon-green); }

    .controls-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(340px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }
    .panel {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 20px;
    }
    .panel h2 {
      margin: 0 0 14px;
      font-size: 15px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      color: var(--neon-cyan);
    }
    .switch-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 14px;
      background: #0c0e18;
      border-radius: 12px;
      margin-bottom: 10px;
      border: 1px solid #1b2035;
    }
    .switch-row .info strong { display: block; font-size: 13px; color: #fff; }
    .switch-row .info span { font-size: 11px; color: var(--muted); }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }
    th, td {
      padding: 12px 10px;
      text-align: right;
      border-bottom: 1px solid #1d2238;
    }
    th { color: var(--muted); font-weight: 600; background: #0c0e18; }
    tr:hover td { background: rgba(255, 255, 255, 0.02); }
    .badge {
      display: inline-block;
      padding: 3px 9px;
      border-radius: 99px;
      font-size: 11px;
      font-weight: 700;
    }
    .badge-online { background: rgba(0, 255, 163, 0.15); color: var(--neon-green); border: 1px solid var(--neon-green); }
    .badge-banned { background: rgba(255, 59, 48, 0.18); color: var(--neon-red); border: 1px solid var(--neon-red); }
    .badge-ok { background: rgba(0, 229, 255, 0.12); color: var(--neon-cyan); }
    .mono { font-family: monospace; font-weight: 700; letter-spacing: 0.5px; }
    .actions-cell { display: flex; gap: 6px; flex-wrap: wrap; }
    #statusBanner {
      display: none;
      padding: 12px 18px;
      border-radius: 12px;
      margin-bottom: 16px;
      font-size: 13px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand">
        <div class="brand-badge">SP</div>
        <div>
          <h1>پنل فرماندهی و امنیت SecretPlay (Cloudflare Edge Admin)</h1>
          <p>کنترل نصب‌ها، مسدودسازی فوری افراد مخرب، مدیریت اتاق‌ها و سیاست‌های امنیتی سرور</p>
        </div>
      </div>
      <div class="auth-bar">
        <input type="password" id="adminKeyInput" placeholder="رمز ادمین (پیش‌فرض: SP-ADMIN-2026)" value="SP-ADMIN-2026" />
        <button class="btn-green" onclick="loadOverview()">🔄 بارگذاری و بروزرسانی</button>
      </div>
    </header>

    <div id="statusBanner"></div>

    <!-- Top Telemetry Metrics -->
    <div class="stats-grid">
      <div class="stat-card">
        <h3>📱 کل دستگاه‌های نصب‌شده</h3>
        <div class="val" id="stTotalDevices">0</div>
        <div class="sub">Unique Installed Devices</div>
      </div>
      <div class="stat-card">
        <h3>🟢 دستگاه‌های فعال اخیر</h3>
        <div class="val" id="stOnlineDevices" style="color: var(--neon-green);">0</div>
        <div class="sub">Active in last 2 mins</div>
      </div>
      <div class="stat-card">
        <h3>🚫 افراد مخرب مسدودشده</h3>
        <div class="val" id="stBannedDevices" style="color: var(--neon-red);">0</div>
        <div class="sub">Globally Banned</div>
      </div>
      <div class="stat-card">
        <h3>🔑 اتاق‌ها و توکن‌های فعال</h3>
        <div class="val" id="stRooms" style="color: var(--neon-cyan);">0</div>
        <div class="sub">Isolated E2EE Rooms</div>
      </div>
      <div class="stat-card">
        <h3>💬 کل پیام‌های رمزنگاری عبوری</h3>
        <div class="val" id="stMessages">0</div>
        <div class="sub">Zero-Knowledge Relayed</div>
      </div>
      <div class="stat-card">
        <h3>📞 کل تماس‌های صوتی و تصویری</h3>
        <div class="val" id="stCalls" style="color: var(--neon-amber);">0</div>
        <div class="sub">WebRTC P2P Sessions</div>
      </div>
    </div>

    <!-- Security Policies & Room Management -->
    <div class="controls-grid">
      <div class="panel">
        <h2>🛡️ سیاست‌های امنیتی سراسری سرور</h2>
        <div class="switch-row">
          <div class="info">
            <strong>🔒 قفل اضطراری کل سرور (Lockdown Mode)</strong>
            <span>در صورت فعال بودن، هیچ دستگاهی اجازه اتصال به سرور را نخواهد داشت</span>
          </div>
          <button id="btnLockdown" class="btn-ghost" onclick="togglePolicy('toggle_lockdown')">خاموش</button>
        </div>
        <div class="switch-row">
          <div class="info">
            <strong>✅ حالت فقط افراد تاییدشده (Strict Whitelist)</strong>
            <span>دستگاه‌های جدید تا زمانی که شما در جدول زیر تاییدشان نکنید مسدود می‌مانند</span>
          </div>
          <button id="btnWhitelist" class="btn-ghost" onclick="togglePolicy('toggle_whitelist')">خاموش</button>
        </div>
        <div style="display:flex; gap:8px; margin-top:14px;">
          <input type="text" id="newAdminKey" placeholder="تغییر رمز ورود پنل ادمین..." style="flex:1;" />
          <button class="btn-amber" onclick="changeAdminKey()">تغییر رمز ادمین</button>
        </div>
      </div>

      <div class="panel">
        <h2>🔑 مدیریت مستقیم اتاق‌ها و توکن‌ها</h2>
        <p style="font-size:12px; color:var(--muted); margin-top:0;">
          می‌توانید هر توکن/اتاقی (مثلاً <span class="mono">SP-1111</span> یا <span class="mono">DM-SP-...</span>) را ریست یا مسدود کنید:
        </p>
        <div style="display:flex; gap:8px; margin-bottom:12px;">
          <input type="text" id="targetRoomInput" placeholder="کد اتاق یا توکن (مثلاً SP-4829-K7)" style="flex:1;" />
          <button class="btn-cyan" onclick="roomAction('reset_room')">♻️ آزادسازی اسلات‌ها</button>
          <button class="btn-red" onclick="roomAction('revoke_room')">🔥 ابطال کامل اتاق</button>
        </div>
        <div style="font-size:12px; color:var(--muted);">
          <strong>اتاق‌های شناسایی‌شده:</strong>
          <div id="roomsChips" style="display:flex; gap:6px; flex-wrap:wrap; margin-top:8px;"></div>
        </div>
        <hr style="border-color:#1d2238; margin:16px 0;" />
        <h2 style="margin-bottom:10px;">🚀 انتشار آپدیت جدید اپلیکیشن (In-App Auto-Updater)</h2>
        <div style="display:grid; grid-template-columns:1fr 110px; gap:8px; margin-bottom:8px;">
          <input type="text" id="updVersion" placeholder="نسخه جدید (مثلاً 2.0.0)" value="2.0.0" />
          <input type="number" id="updBuild" placeholder="Build #" value="8" />
        </div>
        <input type="text" id="updUrl" placeholder="لینک مستقیم دانلود APK..." value="https://github.com/saayedh/SecretPlay/releases/download/v1.0.0/app-arm64-v8a-release.apk" style="width:100%; margin-bottom:8px;" />
        <div style="display:flex; gap:8px;">
          <input type="text" id="updNotes" placeholder="توضیحات آپدیت برای کاربران..." value="نسخه ۲.۰ SecretPlay (Ghost Touch Ultimate): استودیو استیکر وکتور زنده، قلم‌های پیشرفته و کارت‌های هولوگرافیک!" style="flex:1;" />
          <button class="btn-pink" onclick="publishUpdate()">📢 اعلام آپدیت به همه</button>
        </div>
      </div>
    </div>

    <!-- Installed Devices Table -->
    <div class="panel">
      <h2>
        <span>📋 لیست دستگاه‌های نصب‌شده و کاربران (Installed Devices & Moderation)</span>
        <input type="text" id="searchDevice" placeholder="🔍 جستجوی شناسه SP-XXX-XXX یا کشور..." oninput="renderDevicesTable()" style="width:260px;" />
      </h2>
      <div style="overflow-x:auto;">
        <table>
          <thead>
            <tr>
              <th>شماره اختصاصی (Secret ID)</th>
              <th>شناسه سخت‌افزاری (Device ID)</th>
              <th>کشور / IP</th>
              <th>اتاق فعلی</th>
              <th>تعداد اتصال / پیام / تماس</th>
              <th>آخرین فعالیت</th>
              <th>وضعیت</th>
              <th>عملیات مدیریتی (حذف / بن / تایید)</th>
            </tr>
          </thead>
          <tbody id="devicesTableBody">
            <tr><td colspan="8" style="text-align:center; color:var(--muted);">در حال بارگذاری اطلاعات از کلودفلر...</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <script>
    let currentData = { stats: {}, devices: [], rooms: [] };

    function getKey() {
      return document.getElementById('adminKeyInput').value.trim();
    }

    function showBanner(text, isError = false) {
      const el = document.getElementById('statusBanner');
      el.style.display = 'block';
      el.style.background = isError ? 'rgba(255,59,48,0.2)' : 'rgba(0,255,163,0.15)';
      el.style.border = '1px solid ' + (isError ? '#ff3b30' : '#00ffa3');
      el.style.color = isError ? '#ff8a80' : '#00ffa3';
      el.textContent = text;
      setTimeout(() => { el.style.display = 'none'; }, 4000);
    }

    async function loadOverview() {
      try {
        const res = await fetch('/admin/api/overview', {
          headers: { 'X-Admin-Key': getKey() }
        });
        if (!res.ok) {
          showBanner('خطا در احراز هویت ادمین! رمز ادمین را بررسی کنید.', true);
          return;
        }
        currentData = await res.json();
        const s = currentData.stats || {};
        document.getElementById('stTotalDevices').textContent = s.totalInstalledDevices || 0;
        document.getElementById('stOnlineDevices').textContent = s.onlineRecentDevices || 0;
        document.getElementById('stBannedDevices').textContent = s.bannedDevices || 0;
        document.getElementById('stRooms').textContent = s.activeRoomsCount || 0;
        document.getElementById('stMessages').textContent = s.totalMessagesRelayed || 0;
        document.getElementById('stCalls').textContent = s.totalCallsInitiated || 0;

        const btnLock = document.getElementById('btnLockdown');
        btnLock.textContent = s.lockdownMode ? '🔒 فعال (سرور قفل است)' : 'خاموش (عادی)';
        btnLock.className = s.lockdownMode ? 'btn-red' : 'btn-ghost';

        const btnWhite = document.getElementById('btnWhitelist');
        btnWhite.textContent = s.whitelistMode ? '✅ فعال (فقط تاییدشده‌ها)' : 'خاموش (آزاد)';
        btnWhite.className = s.whitelistMode ? 'btn-green' : 'btn-ghost';

        const chips = document.getElementById('roomsChips');
        chips.innerHTML = '';
        (currentData.rooms || []).forEach(r => {
          const span = document.createElement('span');
          span.className = 'badge badge-ok mono';
          span.style.cursor = 'pointer';
          span.textContent = r;
          span.onclick = () => { document.getElementById('targetRoomInput').value = r; };
          chips.appendChild(span);
        });

        renderDevicesTable();
      } catch (e) {
        showBanner('خطا در ارتباط با سرور کلودفلر: ' + e.message, true);
      }
    }

    function formatTimeAgo(ts) {
      if (!ts) return '-';
      const diffSec = Math.floor((Date.now() - ts) / 1000);
      if (diffSec < 60) return 'همین الان (' + diffSec + 's)';
      if (diffSec < 3600) return Math.floor(diffSec / 60) + ' دقیقه پیش';
      if (diffSec < 86400) return Math.floor(diffSec / 3600) + ' ساعت پیش';
      return new Date(ts).toLocaleDateString('fa-IR');
    }

    function renderDevicesTable() {
      const tbody = document.getElementById('devicesTableBody');
      const q = (document.getElementById('searchDevice').value || '').trim().toUpperCase();
      const list = (currentData.devices || []).filter(d => {
        if (!q) return true;
        return (d.secret_number || '').toUpperCase().includes(q) ||
               (d.device_id || '').toUpperCase().includes(q) ||
               (d.room_token || '').toUpperCase().includes(q) ||
               (d.country || '').toUpperCase().includes(q);
      });

      if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align:center; color:var(--muted);">هیچ دستگاهی یافت نشد. به محض اتصال گوشی یا لپ‌تاپ به چت، مشخصات آن اینجا ثبت می‌شود.</td></tr>';
        return;
      }

      tbody.innerHTML = list.map(d => {
        const isBanned = Boolean(d.is_banned);
        const isOnline = (Date.now() - d.last_seen) < 120000 && !isBanned;
        const statusHtml = isBanned
          ? '<span class="badge badge-banned">🚫 مسدود (BANNED)</span>'
          : (isOnline ? '<span class="badge badge-online">🟢 آنلاین</span>' : '<span class="badge badge-ok">⚪ آفلاین</span>');

        return \`<tr>
          <td class="mono" style="color:var(--neon-green); font-size:14px;">\${d.secret_number || 'SP-000-000'}</td>
          <td class="mono" style="color:#cbd5e1;">\${d.device_id}</td>
          <td class="mono">\${d.country || 'UN'} (\${d.ip_masked || ''})</td>
          <td class="mono" style="color:var(--neon-cyan);">\${d.room_token || '-'}</td>
          <td class="mono">🔌 \${d.connect_count} | 💬 \${d.msg_count} | 📞 \${d.call_count}</td>
          <td>\${formatTimeAgo(d.last_seen)}</td>
          <td>\${statusHtml}</td>
          <td>
            <div class="actions-cell">
              \${isBanned
                ? \`<button class="btn-green" onclick="deviceCmd('unban_device', '\${d.device_id}')">🔓 رفع مسدودی</button>\`
                : \`<button class="btn-red" onclick="deviceCmd('ban_device', '\${d.device_id}', '\${d.room_token}')">🚫 بن و اخراج فوری</button>\`
              }
              \${!d.is_approved
                ? \`<button class="btn-cyan" onclick="deviceCmd('approve_device', '\${d.device_id}')">✅ تایید Whitelist</button>\`
                : ''
              }
              <button class="btn-ghost" onclick="deviceCmd('delete_device', '\${d.device_id}')">🗑️ حذف</button>
            </div>
          </td>
        </tr>\`;
      }).join('');
    }

    async function sendAdminCommand(payload) {
      const res = await fetch('/admin/api/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Key': getKey()
        },
        body: JSON.stringify(payload)
      });
      if (res.ok) {
        showBanner('فرمان مدیریتی با موفقیت روی سرور کلودفلر اعمال شد ✓');
        await loadOverview();
      } else {
        showBanner('خطا در اجرای فرمان مدیریتی!', true);
      }
    }

    async function deviceCmd(command, deviceId, roomToken = '') {
      await sendAdminCommand({ command, deviceId, roomToken });
    }

    async function togglePolicy(command) {
      const s = currentData.stats || {};
      const nextVal = command === 'toggle_lockdown' ? !s.lockdownMode : !s.whitelistMode;
      await sendAdminCommand({ command, enabled: nextVal });
    }

    async function roomAction(command) {
      const roomToken = document.getElementById('targetRoomInput').value.trim();
      if (!roomToken) {
        showBanner('لطفاً کد اتاق یا توکن را وارد کنید.', true);
        return;
      }
      await sendAdminCommand({ command, roomToken });
    }

    async function changeAdminKey() {
      const newKey = document.getElementById('newAdminKey').value.trim();
      if (newKey.length < 4) {
        showBanner('رمز جدید ادمین باید حداقل ۴ کاراکتر باشد.', true);
        return;
      }
      await sendAdminCommand({ command: 'change_admin_key', newKey });
      document.getElementById('adminKeyInput').value = newKey;
      document.getElementById('newAdminKey').value = '';
    }

    async function publishUpdate() {
      const latestVersion = document.getElementById('updVersion').value.trim();
      const latestBuild = parseInt(document.getElementById('updBuild').value, 10) || 3;
      const downloadUrl = document.getElementById('updUrl').value.trim();
      const releaseNotes = document.getElementById('updNotes').value.trim();
      const res = await fetch('/admin/api/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Key': getKey()
        },
        body: JSON.stringify({
          command: 'publish_update',
          latestVersion,
          latestBuild,
          downloadUrl,
          releaseNotes,
        })
      });
      if (res.ok) {
        const data = await res.json();
        showBanner('📢 آپدیت منتشر شد! اعلان فوری برای ' + (data.notifiedSockets || 0) + ' کاربر آنلاین (در ' + (data.notifiedRooms || 0) + ' اتاق) ارسال شد ✓');
        await loadOverview();
      } else {
        showBanner('خطا در انتشار آپدیت! رمز ادمین را بررسی کنید.', true);
      }
    }

    loadOverview();
    setInterval(loadOverview, 10000);
  </script>
</body>
</html>`;
