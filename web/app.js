// AirAware Pune — Environmental Intelligence & Real-Time Engine

let API_BASE = window.location.origin.includes(':8000') 
  ? window.location.origin + '/api/v1' 
  : 'http://localhost:8000/api/v1';

let mapInstance = null;
let mapMarkers = [];
let stationChartInstance = null;
let currentTravelMode = 'car';
let allStations = [];
let currentLeaderboard = [];
let selectedZone = 'all';

// Personal Exposure Tracker State
let trackerInterval = null;
let trackerStartTime = null;
let trackerElapsedSec = 0;
let trackerIsRunning = false;

// PWA Install prompt holder
let deferredPrompt = null;

// Initialize on DOM Load
document.addEventListener('DOMContentLoaded', async () => {
  initServiceWorker();
  initPWAInstall();
  initTheme();
  
  await fetchPuneData();
  initLeafletMap();
  populateTrackerWards();

  // Auto-refresh every 60 seconds
  setInterval(refreshData, 60000);
});

// Service Worker for PWA
function initServiceWorker() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(err => {
      console.warn('SW registration skipped:', err);
    });
  }
}

// PWA Installation
function initPWAInstall() {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
    const btn = document.getElementById('pwa-install-btn');
    if (btn) btn.classList.remove('hidden');
  });

  const installBtn = document.getElementById('pwa-install-btn');
  if (installBtn) {
    installBtn.addEventListener('click', async () => {
      if (deferredPrompt) {
        deferredPrompt.prompt();
        const { outcome } = await deferredPrompt.userChoice;
        if (outcome === 'accepted') {
          installBtn.classList.add('hidden');
        }
        deferredPrompt = null;
      }
    });
  }
}

// Theme Toggle
function initTheme() {
  const isDark = localStorage.getItem('airaware-theme') !== 'light';
  applyTheme(isDark);
}

function toggleTheme() {
  const isDark = document.documentElement.classList.contains('dark');
  applyTheme(!isDark);
  localStorage.setItem('airaware-theme', !isDark ? 'dark' : 'light');
  if (mapInstance) {
    updateMapTiles(!isDark);
  }
}

function applyTheme(dark) {
  const sunIcon = document.getElementById('theme-icon-sun');
  const moonIcon = document.getElementById('theme-icon-moon');
  if (dark) {
    document.documentElement.classList.add('dark');
    if (sunIcon) sunIcon.classList.remove('hidden');
    if (moonIcon) moonIcon.classList.add('hidden');
  } else {
    document.documentElement.classList.remove('dark');
    if (sunIcon) sunIcon.classList.add('hidden');
    if (moonIcon) moonIcon.classList.remove('hidden');
  }
}

// Tab Switching
function switchTab(tabId) {
  document.querySelectorAll('.tab-view').forEach(view => {
    view.classList.add('hidden');
  });
  
  const target = document.getElementById(`view-${tabId}`);
  if (target) target.classList.remove('hidden');

  // Update nav link styles
  document.querySelectorAll('.nav-link').forEach(btn => {
    btn.classList.remove('active', 'text-white', 'bg-emerald-600');
    btn.classList.add('text-slate-400');
  });
  const activeNav = document.getElementById(`nav-${tabId}`);
  if (activeNav) {
    activeNav.classList.add('active');
    activeNav.classList.remove('text-slate-400');
  }

  // Mobile nav buttons
  document.querySelectorAll('.mobile-nav-btn').forEach(btn => {
    btn.classList.remove('active');
  });
  const activeMob = document.getElementById(`mob-${tabId}`);
  if (activeMob) activeMob.classList.add('active');

  // If map tab opened, invalidate size
  if (tabId === 'map' && mapInstance) {
    setTimeout(() => { mapInstance.invalidateSize(); }, 200);
  }
}

// Data Fetching & Sync
async function fetchPuneData() {
  setRefreshingUI(true);
  try {
    // 1. Fetch Overview
    const resOverview = await fetch(`${API_BASE}/pune/overview`).catch(() => null);
    if (resOverview && resOverview.ok) {
      const data = await resOverview.json();
      if (data.data) renderOverview(data.data);
    }

    // 2. Fetch Stations & Map
    const resStations = await fetch(`${API_BASE}/pune/stations`).catch(() => null);
    if (resStations && resStations.ok) {
      const data = await resStations.json();
      if (data.data && data.data.length > 0) {
        allStations = data.data;
        renderQuickWards(allStations);
        if (mapInstance) renderMapMarkers(allStations);
      }
    }

    // 3. Fetch Leaderboard
    const resLeaderboard = await fetch(`${API_BASE}/pune/leaderboard`).catch(() => null);
    if (resLeaderboard && resLeaderboard.ok) {
      const data = await resLeaderboard.json();
      if (data.data) {
        currentLeaderboard = data.data;
        renderLeaderboard(currentLeaderboard);
      }
    }

    // 4. Fetch Weather
    const resWeather = await fetch(`${API_BASE}/pune/weather?lat=18.5204&lng=73.8567`).catch(() => null);
    if (resWeather && resWeather.ok) {
      const data = await resWeather.json();
      if (data.data) renderWeather(data.data);
    }

    // 5. Fetch Citizen Reports
    const resReports = await fetch(`${API_BASE}/pune/citizen-reports`).catch(() => null);
    if (resReports && resReports.ok) {
      const data = await resReports.json();
      if (data.data) renderReports(data.data);
    }

    const timeElem = document.getElementById('last-update-time');
    if (timeElem) {
      const now = new Date();
      timeElem.textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
  } catch (err) {
    console.warn('Network sync notice:', err);
  } finally {
    setRefreshingUI(false);
  }
}

async function refreshData() {
  const icon = document.getElementById('refresh-icon');
  if (icon) icon.classList.add('animate-spin');
  await fetchPuneData();
  if (icon) icon.classList.remove('animate-spin');
}

function setRefreshingUI(loading) {
  const ind = document.getElementById('live-indicator');
  if (!ind) return;
  if (loading) {
    ind.classList.add('opacity-75');
  } else {
    ind.classList.remove('opacity-75');
  }
}

// Speedometer & Overview Rendering
function renderOverview(info) {
  const aqiElem = document.getElementById('hero-aqi-value');
  const catBadge = document.getElementById('hero-category-badge');
  const gaugeArc = document.getElementById('gauge-arc');
  const stationsCount = document.getElementById('hero-stations-count');
  const cleanestName = document.getElementById('cleanest-name');
  const cleanestAqi = document.getElementById('cleanest-aqi');
  const pollutedName = document.getElementById('polluted-name');
  const pollutedAqi = document.getElementById('polluted-aqi');
  const bestWindow = document.getElementById('best-window-text');

  const aqi = info.average_aqi || 82;
  const category = info.category || 'Satisfactory';

  if (aqiElem) aqiElem.textContent = aqi;
  if (catBadge) {
    catBadge.textContent = category;
    catBadge.className = `px-3.5 py-1.5 rounded-full text-xs font-extrabold tracking-wide uppercase ${getCategoryBadgeClass(category)}`;
  }

  // Update Gauge SVG stroke-dashoffset (max 251.2, 0 is full, 251.2 is 0)
  if (gaugeArc) {
    const pct = Math.min(1, aqi / 400);
    const offset = 251.2 - (pct * 251.2);
    gaugeArc.style.strokeDashoffset = offset;
    gaugeArc.style.stroke = getCategoryColor(category);
  }

  if (stationsCount && info.stations_active) {
    stationsCount.textContent = `Aggregating ${info.stations_active} official PMC, PCMC & IITM SAFAR stations`;
  }

  if (cleanestName && info.cleanest_locality) {
    cleanestName.textContent = info.cleanest_locality.name;
    cleanestAqi.textContent = `AQI ${info.cleanest_locality.aqi}`;
  }

  if (pollutedName && info.polluted_locality) {
    pollutedName.textContent = info.polluted_locality.name;
    pollutedAqi.textContent = `AQI ${info.polluted_locality.aqi}`;
  }

  if (bestWindow && info.best_outdoor_window) {
    bestWindow.textContent = info.best_outdoor_window;
  }

  // Advisory text
  if (info.health_advisory) {
    const adv = info.health_advisory;
    if (document.getElementById('advisory-walks')) document.getElementById('advisory-walks').textContent = adv.morning_walks || '';
    if (document.getElementById('advisory-sensitive')) document.getElementById('advisory-sensitive').textContent = adv.sensitive_groups || '';
    if (document.getElementById('advisory-mask')) document.getElementById('advisory-mask').textContent = adv.mask_needed ? 'N95 mask recommended for all outdoor transit.' : 'Masks optional in residential wards; recommended on Pune bypass.';
    if (document.getElementById('advisory-vent')) document.getElementById('advisory-vent').textContent = adv.ventilation || '';
  }

  // High pollution banner
  const alertBanner = document.getElementById('city-alert-banner');
  if (alertBanner) {
    if (aqi > 150) {
      alertBanner.classList.remove('hidden');
      alertBanner.className = 'p-4 rounded-2xl border flex items-start gap-3 bg-amber-950/40 border-amber-500/40 text-amber-200';
      document.getElementById('alert-banner-title').textContent = `Pune Air Alert: ${category} Air Quality`;
      document.getElementById('alert-banner-msg').textContent = info.health_advisory ? info.health_advisory.general : 'Elevated particulate levels. Vulnerable citizens should exercise caution.';
    } else {
      alertBanner.classList.add('hidden');
    }
  }
}

// Weather Rendering
function renderWeather(w) {
  if (document.getElementById('weather-temp')) {
    document.getElementById('weather-temp').textContent = `${w.temperature_c.toFixed(1)}°C`;
  }
  if (document.getElementById('weather-humidity')) {
    document.getElementById('weather-humidity').textContent = `${Math.round(w.humidity_pct)}%`;
  }
  if (document.getElementById('weather-wind')) {
    const kmh = (w.wind_speed_ms * 3.6).toFixed(0);
    document.getElementById('weather-wind').textContent = `${kmh} km/h`;
  }
  if (document.getElementById('weather-dir')) {
    document.getElementById('weather-dir').textContent = `${getWindCompass(w.wind_direction_deg)} ${Math.round(w.wind_direction_deg)}°`;
  }
}

function getWindCompass(deg) {
  const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  return directions[Math.round(deg / 22.5) % 16];
}

// Quick Ward Carousel Cards
function renderQuickWards(stations) {
  const container = document.getElementById('quick-ward-cards');
  if (!container) return;
  container.innerHTML = '';

  stations.slice(0, 12).forEach(st => {
    const aqi = st.aqi_value || 75;
    const cat = st.aqi_category || 'Satisfactory';
    const area = st.area || st.name.split(',')[0];
    
    const card = document.createElement('div');
    card.className = 'bg-slate-900/60 hover:bg-slate-800/80 border border-slate-800/80 p-3 rounded-2xl cursor-pointer transition flex flex-col justify-between';
    card.onclick = () => openStationModal(st.id);
    card.innerHTML = `
      <div>
        <div class="flex items-center justify-between">
          <span class="text-[10px] font-bold uppercase tracking-wider text-slate-400">${st.dominant_pollutant || 'PM2.5'}</span>
          <span class="w-2 h-2 rounded-full ${getCategoryDotClass(cat)}"></span>
        </div>
        <p class="font-heading font-bold text-sm text-white truncate mt-1">${area}</p>
      </div>
      <div class="mt-2 flex items-baseline justify-between">
        <span class="text-xl font-heading font-black text-white">${aqi}</span>
        <span class="text-[10px] font-bold ${getCategoryTextClass(cat)}">${cat}</span>
      </div>
    `;
    container.appendChild(card);
  });
}

// Leaflet Map Initialization
let mapTileLayer = null;

function initLeafletMap() {
  const mapContainer = document.getElementById('leaflet-map');
  if (!mapContainer || mapInstance) return;

  // Center on Pune Metropolitan Region
  mapInstance = L.map('leaflet-map', {
    zoomControl: false,
  }).setView([18.5300, 73.8500], 12);

  L.control.zoom({ position: 'bottomleft' }).addTo(mapInstance);

  const isDark = document.documentElement.classList.contains('dark');
  const tileUrl = isDark
    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

  mapTileLayer = L.tileLayer(tileUrl, {
    attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
    subdomains: 'abcd',
    maxZoom: 19
  }).addTo(mapInstance);

  if (allStations.length > 0) {
    renderMapMarkers(allStations);
  }
}

function updateMapTiles(isDark) {
  if (!mapInstance || !mapTileLayer) return;
  mapInstance.removeLayer(mapTileLayer);
  const tileUrl = isDark
    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  mapTileLayer = L.tileLayer(tileUrl, {
    attribution: '&copy; OpenStreetMap &copy; CARTO',
    subdomains: 'abcd',
    maxZoom: 19
  }).addTo(mapInstance);
}

function recenterMap() {
  if (mapInstance) {
    mapInstance.flyTo([18.5300, 73.8500], 12, { duration: 1.2 });
  }
}

function renderMapMarkers(stations) {
  if (!mapInstance) return;

  // Clear existing
  mapMarkers.forEach(m => mapInstance.removeLayer(m));
  mapMarkers = [];

  stations.forEach(st => {
    if (!st.latitude || !st.longitude) return;
    const aqi = st.aqi_value || 75;
    const cat = st.aqi_category || 'Satisfactory';
    const area = st.area || st.name.split(',')[0];
    const pinClass = getPinClass(cat);

    // Custom HTML Marker Pin
    const customIcon = L.divIcon({
      className: 'custom-div-icon',
      html: `<div class="aqi-map-pin ${pinClass}" style="width: 38px; height: 38px;">${aqi}</div>`,
      iconSize: [38, 38],
      iconAnchor: [19, 19]
    });

    const marker = L.marker([st.latitude, st.longitude], { icon: customIcon }).addTo(mapInstance);
    
    // Popup content
    const popupHtml = `
      <div class="p-1 space-y-2 min-w-[190px]">
        <div class="flex items-center justify-between border-b border-slate-700/60 pb-1.5">
          <span class="text-[10px] font-bold uppercase tracking-wider text-emerald-400">${st.source_code || 'CPCB/IITM'}</span>
          <span class="text-[10px] px-2 py-0.5 rounded-full ${getCategoryBadgeClass(cat)} font-bold">${cat}</span>
        </div>
        <div>
          <h4 class="font-heading font-extrabold text-base text-white">${area}</h4>
          <p class="text-[11px] text-slate-300">${st.name}</p>
        </div>
        <div class="flex items-baseline justify-between bg-slate-900/80 p-2 rounded-xl border border-slate-800">
          <span class="text-xs text-slate-400">Current AQI</span>
          <span class="text-2xl font-black text-white font-heading">${aqi}</span>
        </div>
        <button onclick="openStationModal('${st.id}')" class="w-full py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold transition">
          View 24h Trend Chart &rarr;
        </button>
      </div>
    `;

    marker.bindPopup(popupHtml);
    marker.stationData = st;
    mapMarkers.push(marker);
  });
}

function setMapFilter(filter) {
  document.querySelectorAll('.map-chip').forEach(c => {
    c.classList.remove('active', 'bg-emerald-600', 'text-white');
    c.classList.add('bg-slate-800', 'text-slate-300');
  });
  event.target.classList.add('active', 'bg-emerald-600', 'text-white');
  event.target.classList.remove('bg-slate-800', 'text-slate-300');

  mapMarkers.forEach(m => {
    const aqi = m.stationData.aqi_value || 75;
    if (filter === 'all') {
      m.addTo(mapInstance);
    } else if (filter === 'good') {
      if (aqi <= 100) m.addTo(mapInstance);
      else mapInstance.removeLayer(m);
    } else if (filter === 'moderate') {
      if (aqi > 100) m.addTo(mapInstance);
      else mapInstance.removeLayer(m);
    }
  });
}

// Leaderboard Rendering
function renderLeaderboard(list) {
  const container = document.getElementById('leaderboard-container');
  if (!container) return;
  container.innerHTML = '';

  list.forEach(it => {
    const card = document.createElement('div');
    card.className = 'bg-slate-900/80 hover:bg-slate-800/80 border border-slate-800/80 p-5 rounded-3xl backdrop-blur-xl shadow-xl transition flex flex-col justify-between cursor-pointer';
    card.onclick = () => openStationModal(it.id);
    
    card.innerHTML = `
      <div>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="w-6 h-6 rounded-lg bg-slate-950 flex items-center justify-center text-xs font-bold text-slate-400">#${it.rank}</span>
            <span class="text-xs px-2.5 py-0.5 rounded-full bg-slate-800 text-slate-300 text-[10px] font-semibold">${it.zone_type}</span>
          </div>
          <span class="text-xs px-2.5 py-1 rounded-full ${getCategoryBadgeClass(it.category)} font-bold">${it.category}</span>
        </div>
        <h4 class="font-heading font-extrabold text-lg text-white mt-2">${it.locality}</h4>
        <p class="text-xs text-slate-400 truncate">${it.station_name}</p>
      </div>

      <div class="mt-4 pt-3 border-t border-slate-800/80 flex items-end justify-between">
        <div>
          <span class="text-[10px] text-slate-400 uppercase tracking-wider block">Dominant</span>
          <span class="text-xs font-bold text-teal-400 uppercase">${it.dominant_pollutant}</span>
        </div>
        <div class="text-right">
          <span class="text-[10px] text-slate-400 uppercase tracking-wider block">CPCB NAQI</span>
          <span class="text-3xl font-heading font-black text-white">${it.aqi}</span>
        </div>
      </div>
    `;
    container.appendChild(card);
  });
}

function filterLeaderboard() {
  const query = document.getElementById('leaderboard-search').value.toLowerCase();
  let filtered = currentLeaderboard.filter(it => 
    it.locality.toLowerCase().includes(query) || it.station_name.toLowerCase().includes(query)
  );
  if (selectedZone !== 'all') {
    filtered = filtered.filter(it => it.zone_type === selectedZone);
  }
  renderLeaderboard(filtered);
}

function filterByZone(zone) {
  selectedZone = zone;
  document.querySelectorAll('.zone-chip').forEach(c => {
    c.classList.remove('active', 'bg-emerald-600', 'text-white');
    c.classList.add('bg-slate-900', 'text-slate-300');
  });
  event.target.classList.add('active', 'bg-emerald-600', 'text-white');
  event.target.classList.remove('bg-slate-900', 'text-slate-300');
  filterLeaderboard();
}

// Station Details Modal & 24h Chart
async function openStationModal(stationId) {
  const modal = document.getElementById('station-modal');
  if (!modal) return;
  modal.classList.remove('hidden');
  modal.classList.add('flex');

  // Fetch station details
  try {
    const res = await fetch(`${API_BASE}/pune/stations/${stationId}`);
    if (res.ok) {
      const data = (await res.json()).data;
      if (data) {
        document.getElementById('modal-station-name').textContent = data.station.name;
        document.getElementById('modal-station-area').textContent = data.station.area || 'Pune';
        document.getElementById('modal-station-source').textContent = data.station.source_code || 'Official CPCB/IITM';
        document.getElementById('modal-station-coords').textContent = `${data.station.latitude.toFixed(4)}° N, ${data.station.longitude.toFixed(4)}° E`;

        const aqi = data.aqi ? data.aqi.aqi_value : 80;
        const cat = data.aqi ? data.aqi.aqi_category : 'Satisfactory';
        document.getElementById('modal-aqi-value').textContent = aqi;
        document.getElementById('modal-cat-badge').textContent = cat;
        document.getElementById('modal-cat-badge').className = `px-3.5 py-1.5 rounded-full text-xs font-bold uppercase ${getCategoryBadgeClass(cat)}`;
        document.getElementById('modal-dom-pollutant').textContent = `Dominant: ${(data.aqi?.dominant_pollutant || 'PM2.5').toUpperCase()}`;

        // Render Pollutants
        const pollGrid = document.getElementById('modal-pollutants-grid');
        pollGrid.innerHTML = '';
        if (data.pollutants) {
          data.pollutants.forEach(p => {
            const el = document.createElement('div');
            el.className = 'bg-slate-950 p-2.5 rounded-xl border border-slate-800 text-center';
            el.innerHTML = `
              <span class="text-[10px] text-slate-400 font-semibold block uppercase">${p.code}</span>
              <span class="text-sm font-bold text-white">${p.value.toFixed(1)}</span>
              <span class="text-[9px] text-slate-500 block">${p.unit}</span>
            `;
            pollGrid.appendChild(el);
          });
        }
      }
    }

    // Fetch 24-hour History for Chart
    const resHist = await fetch(`${API_BASE}/pune/stations/${stationId}/history?hours=24`);
    if (resHist.ok) {
      const histData = (await resHist.json()).data || [];
      renderHistoryChart(histData);
    }
  } catch (e) {
    console.error('Station modal error:', e);
  }
}

function closeStationModal() {
  const modal = document.getElementById('station-modal');
  if (modal) {
    modal.classList.add('hidden');
    modal.classList.remove('flex');
  }
}

function renderHistoryChart(hist) {
  const canvas = document.getElementById('station-trend-chart');
  if (!canvas) return;

  if (stationChartInstance) {
    stationChartInstance.destroy();
  }

  const labels = hist.map(h => {
    const d = new Date(h.computed_for);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  });
  const values = hist.map(h => h.aqi_value);

  const ctx = canvas.getContext('2d');
  const gradient = ctx.createLinearGradient(0, 0, 0, 200);
  gradient.addColorStop(0, 'rgba(16, 185, 129, 0.4)');
  gradient.addColorStop(1, 'rgba(16, 185, 129, 0.0)');

  stationChartInstance = new Chart(ctx, {
    type: 'line',
    data: {
      labels: labels,
      datasets: [{
        label: 'CPCB AQI',
        data: values,
        borderColor: '#10B981',
        backgroundColor: gradient,
        borderWidth: 2.5,
        tension: 0.35,
        fill: true,
        pointBackgroundColor: '#10B981',
        pointRadius: 2.5
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: '#0F172A',
          borderColor: '#334155',
          borderWidth: 1,
          titleFont: { family: 'Plus Jakarta Sans', size: 12 },
          bodyFont: { family: 'Plus Jakarta Sans', size: 12 }
        }
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: { color: '#64748B', font: { size: 10 } }
        },
        y: {
          grid: { color: '#1E293B' },
          ticks: { color: '#64748B', font: { size: 10 } }
        }
      }
    }
  });
}

// Route Exposure Planner
function setTravelMode(mode) {
  currentTravelMode = mode;
  document.querySelectorAll('.mode-btn').forEach(btn => {
    btn.classList.remove('active', 'border-emerald-500/40', 'bg-emerald-500/10', 'text-emerald-300');
    btn.classList.add('border-slate-800', 'bg-slate-950', 'text-slate-400');
  });
  event.currentTarget.classList.add('active', 'border-emerald-500/40', 'bg-emerald-500/10', 'text-emerald-300');
  event.currentTarget.classList.remove('border-slate-800', 'bg-slate-950', 'text-slate-400');
}

async function calculateRouteExposure() {
  const start = document.getElementById('route-start').value;
  const end = document.getElementById('route-end').value;

  try {
    const res = await fetch(`${API_BASE}/pune/route-exposure`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        start_point: start,
        end_point: end,
        mode: currentTravelMode
      })
    });

    if (res.ok) {
      const data = (await res.json()).data;
      if (data) {
        document.getElementById('route-distance').textContent = `${data.distance_km} km`;
        document.getElementById('route-duration').textContent = `${data.duration_minutes} mins`;
        document.getElementById('route-avg-aqi').textContent = data.average_aqi;
        document.getElementById('route-cat-badge').textContent = `${data.category} Route`;
        document.getElementById('route-pm25-inhaled').textContent = `${data.estimated_pm25_inhaled_ug} µg`;
        
        if (data.recommended_route) {
          document.getElementById('route-alt-name').textContent = data.recommended_route.name;
          document.getElementById('route-alt-note').textContent = data.recommended_route.note;
        }

        const tipsList = document.getElementById('route-tips-list');
        if (tipsList && data.tips) {
          tipsList.innerHTML = data.tips.map(t => `<li>• ${t}</li>`).join('');
        }
      }
    }
  } catch (err) {
    console.error('Route exposure error:', err);
  }
}

// Personal Exposure Tracker
function populateTrackerWards() {
  const wardSelect = document.getElementById('tracker-ward');
  if (!wardSelect) return;
  const puneWards = [
    'Pashan (IITM Reserve)',
    'Baner',
    'Aundh',
    'Kothrud',
    'Shivajinagar / FC Road',
    'Hinjawadi Phase 1',
    'Viman Nagar / Airport',
    'Katraj',
    'Hadapsar / Magarpatta',
    'Bhosari Industrial',
    'Swargate Hub'
  ];
  wardSelect.innerHTML = puneWards.map(w => `<option value="${w}">${w}</option>`).join('');
}

function toggleTrackerSession() {
  const btnText = document.getElementById('tracker-btn-text');
  const btn = document.getElementById('tracker-start-btn');
  const statusInd = document.getElementById('tracker-status-indicator');

  if (!trackerIsRunning) {
    // Start
    trackerIsRunning = true;
    trackerStartTime = Date.now() - (trackerElapsedSec * 1000);
    trackerInterval = setInterval(updateTrackerTick, 1000);
    btnText.textContent = 'Pause Session';
    btn.className = 'flex-1 py-3.5 rounded-2xl bg-amber-600 hover:bg-amber-500 text-white font-bold text-sm shadow-lg shadow-amber-600/30 transition flex items-center justify-center gap-2';
    if (statusInd) statusInd.textContent = 'SESSION IN PROGRESS • RECORDING EXPOSURE';
  } else {
    // Pause
    trackerIsRunning = false;
    clearInterval(trackerInterval);
    btnText.textContent = 'Resume Session';
    btn.className = 'flex-1 py-3.5 rounded-2xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-sm shadow-lg shadow-emerald-600/30 transition flex items-center justify-center gap-2';
    if (statusInd) statusInd.textContent = 'PAUSED';
  }
}

function updateTrackerTick() {
  trackerElapsedSec = Math.floor((Date.now() - trackerStartTime) / 1000);
  
  const hrs = String(Math.floor(trackerElapsedSec / 3600)).padStart(2, '0');
  const mins = String(Math.floor((trackerElapsedSec % 3600) / 60)).padStart(2, '0');
  const secs = String(trackerElapsedSec % 60).padStart(2, '0');
  document.getElementById('tracker-timer').textContent = `${hrs}:${mins}:${secs}`;

  // Inhalation calculation
  const act = document.getElementById('tracker-activity').value;
  const rates = { running: 45, cycling: 40, walking: 25, commute: 20 };
  const ratePerMin = rates[act] || 25;
  const totalLiters = (ratePerMin / 60.0) * trackerElapsedSec;
  
  // Ambient PM2.5 assumption for Pune (average ~40 ug/m3 = 0.04 ug/L)
  const pm25Ug = totalLiters * 0.042;
  const dailyQuotaPct = Math.min(100, Math.round((pm25Ug / 25.0) * 100));

  document.getElementById('track-air-liters').textContent = totalLiters.toFixed(1);
  document.getElementById('track-pm25-ug').textContent = pm25Ug.toFixed(2);
  document.getElementById('track-safety-pct').textContent = `${dailyQuotaPct}%`;

  const bar = document.getElementById('tracker-progress-bar');
  if (bar) bar.style.width = `${dailyQuotaPct}%`;
}

function resetTrackerSession() {
  trackerIsRunning = false;
  clearInterval(trackerInterval);
  trackerElapsedSec = 0;
  document.getElementById('tracker-timer').textContent = '00:00:00';
  document.getElementById('track-air-liters').textContent = '0.0';
  document.getElementById('track-pm25-ug').textContent = '0.0';
  document.getElementById('track-safety-pct').textContent = '0%';
  document.getElementById('tracker-btn-text').textContent = 'Start Exposure Session';
  document.getElementById('tracker-start-btn').className = 'flex-1 py-3.5 rounded-2xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-sm shadow-lg shadow-emerald-600/30 transition flex items-center justify-center gap-2';
  document.getElementById('tracker-status-indicator').textContent = 'READY TO START';
  const bar = document.getElementById('tracker-progress-bar');
  if (bar) bar.style.width = '0%';
}

// Citizen AirWatch Incident Reports
function renderReports(reports) {
  const container = document.getElementById('reports-feed');
  if (!container) return;
  container.innerHTML = '';

  reports.forEach(r => {
    const card = document.createElement('div');
    card.className = 'bg-slate-900/80 border border-slate-800/80 p-5 rounded-3xl backdrop-blur-xl shadow-xl flex flex-col justify-between space-y-3';
    card.innerHTML = `
      <div>
        <div class="flex items-center justify-between">
          <span class="text-xs px-2.5 py-0.5 rounded-full bg-slate-800 text-emerald-400 font-bold">${r.ward}</span>
          <span class="text-[10px] px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-semibold">${r.status}</span>
        </div>
        <h4 class="font-heading font-extrabold text-base text-white mt-2">${r.category}</h4>
        <p class="text-xs text-slate-300 mt-1">${r.description}</p>
      </div>

      <div class="pt-3 border-t border-slate-800 flex items-center justify-between text-xs">
        <span class="text-slate-500 font-mono text-[11px]">${formatTimeAgo(r.reported_at)}</span>
        <button onclick="upvoteReport('${r.id}', this)" class="flex items-center gap-1.5 px-3 py-1 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 font-bold transition">
          <span>▲</span>
          <span>${r.votes} Verify</span>
        </button>
      </div>
    `;
    container.appendChild(card);
  });
}

function openReportModal() {
  const modal = document.getElementById('report-modal');
  if (modal) {
    modal.classList.remove('hidden');
    modal.classList.add('flex');
  }
}

function closeReportModal() {
  const modal = document.getElementById('report-modal');
  if (modal) {
    modal.classList.add('hidden');
    modal.classList.remove('flex');
  }
}

async function submitCitizenReport(e) {
  e.preventDefault();
  const ward = document.getElementById('report-ward').value;
  const category = document.getElementById('report-category').value;
  const description = document.getElementById('report-desc').value;

  try {
    const res = await fetch(`${API_BASE}/pune/citizen-reports`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ward, category, description })
    });
    if (res.ok) {
      closeReportModal();
      document.getElementById('citizen-report-form').reset();
      // Re-fetch reports
      const repRes = await fetch(`${API_BASE}/pune/citizen-reports`);
      if (repRes.ok) {
        renderReports((await repRes.json()).data);
      }
    }
  } catch (err) {
    console.error('Submit report error:', err);
  }
}

function upvoteReport(id, btn) {
  const countSpan = btn.querySelector('span:last-child');
  if (countSpan) {
    let num = parseInt(countSpan.textContent) || 0;
    countSpan.textContent = `${num + 1} Verified`;
    btn.disabled = true;
    btn.classList.add('text-emerald-400', 'bg-emerald-500/10');
  }
}

// Utility Helpers
function getCategoryColor(cat) {
  switch (cat?.toLowerCase()) {
    case 'good': return '#10B981';
    case 'satisfactory': return '#84CC16';
    case 'moderate': return '#F59E0B';
    case 'poor': return '#F97316';
    case 'very poor': return '#EF4444';
    case 'severe': return '#7F1D1D';
    default: return '#10B981';
  }
}

function getCategoryBadgeClass(cat) {
  switch (cat?.toLowerCase()) {
    case 'good': return 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30';
    case 'satisfactory': return 'bg-lime-500/20 text-lime-300 border border-lime-500/30';
    case 'moderate': return 'bg-amber-500/20 text-amber-300 border border-amber-500/30';
    case 'poor': return 'bg-orange-500/20 text-orange-300 border border-orange-500/30';
    case 'very poor': return 'bg-red-500/20 text-red-300 border border-red-500/30';
    case 'severe': return 'bg-red-900/30 text-red-200 border border-red-900/50';
    default: return 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30';
  }
}

function getCategoryTextClass(cat) {
  switch (cat?.toLowerCase()) {
    case 'good': return 'text-emerald-400';
    case 'satisfactory': return 'text-lime-400';
    case 'moderate': return 'text-amber-400';
    case 'poor': return 'text-orange-400';
    case 'very poor': return 'text-red-400';
    case 'severe': return 'text-red-600';
    default: return 'text-emerald-400';
  }
}

function getCategoryDotClass(cat) {
  switch (cat?.toLowerCase()) {
    case 'good': return 'bg-emerald-500';
    case 'satisfactory': return 'bg-lime-500';
    case 'moderate': return 'bg-amber-500';
    case 'poor': return 'bg-orange-500';
    case 'very poor': return 'bg-red-500';
    case 'severe': return 'bg-red-700';
    default: return 'bg-emerald-500';
  }
}

function getPinClass(cat) {
  switch (cat?.toLowerCase()) {
    case 'good': return 'aqi-pin-good';
    case 'satisfactory': return 'aqi-pin-satisfactory';
    case 'moderate': return 'aqi-pin-moderate';
    case 'poor': return 'aqi-pin-poor';
    case 'very poor': return 'aqi-pin-verypoor';
    case 'severe': return 'aqi-pin-severe';
    default: return 'aqi-pin-satisfactory';
  }
}

function formatTimeAgo(isoStr) {
  if (!isoStr) return '';
  const diffMs = Date.now() - new Date(isoStr).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}
