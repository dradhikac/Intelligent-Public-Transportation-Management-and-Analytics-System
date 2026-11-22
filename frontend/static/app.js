/**
 * TransitIQ - Intelligent Public Transportation Management & Analytics System
 * Client-Side Application Core
 */

const API_BASE = window.location.origin;

// State management
let currentTab = 'dashboard';
let fleetChartInstance = null;
let passengerChartInstance = null;
let leafletMap = null;
let mapMarkers = [];

// Initialize application on DOM ready
document.addEventListener('DOMContentLoaded', () => {
    checkSystemHealth();
    loadDashboard();
    initModalsData();

    // Auto-refresh every 20 seconds
    setInterval(() => {
        if (currentTab === 'dashboard') {
            loadDashboard(false);
        }
    }, 20000);
});

// Toast notification utility
function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    
    let iconName = 'info';
    if (type === 'success') iconName = 'check-circle';
    if (type === 'error') iconName = 'alert-triangle';

    toast.innerHTML = `
        <i data-lucide="${iconName}" class="w-4 h-4"></i>
        <span>${message}</span>
    `;
    container.appendChild(toast);
    lucide.createIcons();

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(100%)';
        toast.style.transition = 'all 0.3s ease-out';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

// System Health Check
async function checkSystemHealth() {
    const badge = document.getElementById('db-status-badge');
    const text = document.getElementById('db-status-text');
    try {
        const res = await fetch(`${API_BASE}/api/system/health`);
        const data = await res.json();
        if (data.status === 'HEALTHY') {
            text.textContent = `Connected: ${data.database.name} (${data.database.tables_count} Tables)`;
            badge.className = "flex items-center space-x-2 bg-emerald-950/60 border border-emerald-500/40 px-3 py-1.5 rounded-full text-xs text-emerald-300";
        } else {
            text.textContent = "DB Degraded";
            badge.className = "flex items-center space-x-2 bg-amber-950/60 border border-amber-500/40 px-3 py-1.5 rounded-full text-xs text-amber-300";
        }
    } catch (e) {
        text.textContent = "Offline / Connection Error";
        badge.className = "flex items-center space-x-2 bg-rose-950/60 border border-rose-500/40 px-3 py-1.5 rounded-full text-xs text-rose-300";
    }
}

// Tab Switching
function switchTab(tabName) {
    currentTab = tabName;

    // Update Sidebar Navigation highlights
    document.querySelectorAll('.nav-item').forEach(btn => {
        btn.classList.remove('bg-indigo-600/20', 'border-indigo-500/30', 'text-indigo-300', 'text-white');
        btn.classList.add('text-slate-400');
    });
    const activeNav = document.getElementById(`nav-${tabName}`);
    if (activeNav) {
        activeNav.classList.remove('text-slate-400');
        activeNav.classList.add('bg-indigo-600/20', 'border', 'border-indigo-500/30', 'text-indigo-300', 'text-white');
    }

    // Toggle Content Views
    document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
    const activeView = document.getElementById(`view-${tabName}`);
    if (activeView) activeView.classList.remove('hidden');

    // Trigger tab-specific loader
    if (tabName === 'dashboard') loadDashboard();
    else if (tabName === 'fleet') loadFleetTab();
    else if (tabName === 'routes') loadRoutesTab();
    else if (tabName === 'trips') loadTripsTab();
    else if (tabName === 'passengers') loadPassengersTab();
    else if (tabName === 'delays') loadDelaysTab();
    else if (tabName === 'drivers') loadDriversTab();
    else if (tabName === 'audit') loadAuditTab();

    lucide.createIcons();
}

function refreshCurrentView() {
    const icon = document.getElementById('refresh-icon');
    if (icon) icon.classList.add('animate-spin');
    switchTab(currentTab);
    setTimeout(() => {
        if (icon) icon.classList.remove('animate-spin');
    }, 600);
}

// ---------------------------------------------------------------------
// 1. DASHBOARD OVERVIEW LOADER
// ---------------------------------------------------------------------
async function loadDashboard(showNotification = true) {
    try {
        // Fetch KPIs
        const kpiRes = await fetch(`${API_BASE}/api/analytics/kpis`);
        const kpis = await kpiRes.json();

        document.getElementById('kpi-total-buses').textContent = kpis.total_buses || 0;
        document.getElementById('kpi-active-buses').textContent = `${kpis.active_buses || 0} Active`;
        document.getElementById('kpi-total-trips').textContent = kpis.total_trips || 0;
        document.getElementById('kpi-running-trips').textContent = `${kpis.running_trips || 0} Running`;
        document.getElementById('kpi-total-passengers').textContent = (kpis.total_passengers_served || 0).toLocaleString();
        document.getElementById('kpi-on-time-rate').textContent = `${kpis.on_time_rate_pct || 100}%`;
        document.getElementById('kpi-severe-delays').textContent = `${kpis.severe_delays_count || 0} Severe Delays`;

        // Fetch Recent Trips
        const tripsRes = await fetch(`${API_BASE}/api/trips?limit=6`);
        const trips = await tripsRes.json();
        const tripsTbody = document.getElementById('overview-trips-tbody');
        if (trips.length > 0) {
            tripsTbody.innerHTML = trips.map(t => `
                <tr>
                    <td class="font-mono text-indigo-400 font-semibold">#${t.trip_id}</td>
                    <td>
                        <span class="font-bold text-slate-200">${t.route_number}</span>
                        <span class="text-xs text-slate-500 block truncate max-w-[150px]">${t.route_name}</span>
                    </td>
                    <td class="font-mono text-slate-300">${t.registration_number}</td>
                    <td class="text-slate-300">${t.driver_name}</td>
                    <td class="text-xs text-slate-400 font-mono">${t.service_date}</td>
                    <td><span class="badge badge-${t.trip_status.toLowerCase()}">${t.trip_status}</span></td>
                </tr>
            `).join('');
        } else {
            tripsTbody.innerHTML = `<tr><td colspan="6" class="text-center text-slate-500 py-6">No trips found.</td></tr>`;
        }

        // Fetch Recent Delays
        const delaysRes = await fetch(`${API_BASE}/api/delays/analysis`);
        const delays = await delaysRes.json();
        const delaysContainer = document.getElementById('overview-delays-list');
        if (delays.length > 0) {
            delaysContainer.innerHTML = delays.slice(0, 5).map(d => `
                <div class="p-2.5 rounded-lg bg-slate-900 border border-slate-800 flex items-start justify-between">
                    <div>
                        <div class="flex items-center space-x-2">
                            <span class="font-semibold text-xs text-slate-200">${d.reason_name}</span>
                            <span class="badge badge-${d.severity.toLowerCase()}">${d.severity}</span>
                        </div>
                        <p class="text-[11px] text-slate-400 mt-1">Route ${d.route_number} at ${d.stop_name}</p>
                    </div>
                    <span class="font-mono text-xs text-amber-400 font-bold">${Math.round(d.delay_seconds / 60)}m (${d.delay_seconds}s)</span>
                </div>
            `).join('');
        } else {
            delaysContainer.innerHTML = `<div class="text-xs text-slate-500 text-center py-6">No recent delay incidents reported.</div>`;
        }

        // Render Charts
        renderDashboardCharts();
        lucide.createIcons();
    } catch (e) {
        console.error("Dashboard error:", e);
    }
}

async function renderDashboardCharts() {
    try {
        // Fleet availability chart
        const fleetRes = await fetch(`${API_BASE}/api/fleet/summary`);
        const fleet = await fleetRes.json();

        const statusCounts = {};
        fleet.forEach(b => {
            statusCounts[b.operational_status] = (statusCounts[b.operational_status] || 0) + 1;
        });

        const fleetCtx = document.getElementById('chart-fleet-availability');
        if (fleetCtx) {
            if (fleetChartInstance) fleetChartInstance.destroy();
            fleetChartInstance = new Chart(fleetCtx, {
                type: 'doughnut',
                data: {
                    labels: Object.keys(statusCounts),
                    datasets: [{
                        data: Object.values(statusCounts),
                        backgroundColor: ['#10b981', '#f43f5e', '#6b7280', '#f59e0b'],
                        borderWidth: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { position: 'bottom', labels: { color: '#9ca3af', font: { size: 11 } } }
                    }
                }
            });
        }

        // Passenger demand chart
        const demandRes = await fetch(`${API_BASE}/api/analytics/passenger-demand`);
        const demand = await demandRes.json();

        const topStops = demand.slice(0, 7);
        const passCtx = document.getElementById('chart-passenger-demand');
        if (passCtx) {
            if (passengerChartInstance) passengerChartInstance.destroy();
            passengerChartInstance = new Chart(passCtx, {
                type: 'bar',
                data: {
                    labels: topStops.map(s => s.stop_name),
                    datasets: [
                        { label: 'Boardings', data: topStops.map(s => s.total_boardings), backgroundColor: '#6366f1' },
                        { label: 'Alightings', data: topStops.map(s => s.total_alightings), backgroundColor: '#3b82f6' }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: { ticks: { color: '#9ca3af', font: { size: 10 } }, grid: { display: false } },
                        y: { ticks: { color: '#9ca3af' }, grid: { color: '#1f2937' } }
                    },
                    plugins: {
                        legend: { position: 'top', labels: { color: '#9ca3af', font: { size: 11 } } }
                    }
                }
            });
        }
    } catch (e) {
        console.error("Chart render error:", e);
    }
}


// ---------------------------------------------------------------------
// 2. FLEET TAB LOADER
// ---------------------------------------------------------------------
async function loadFleetTab() {
    const statusFilter = document.getElementById('fleet-filter-status')?.value || '';
    const url = statusFilter ? `${API_BASE}/api/fleet/buses?status=${statusFilter}` : `${API_BASE}/api/fleet/buses`;
    
    try {
        const [busesRes, maintRes] = await Promise.all([
            fetch(url),
            fetch(`${API_BASE}/api/fleet/maintenance`)
        ]);
        const buses = await busesRes.json();
        const maints = await maintRes.json();

        // Render Buses
        const tbody = document.getElementById('fleet-buses-tbody');
        tbody.innerHTML = buses.map(b => `
            <tr>
                <td class="font-mono text-indigo-400 font-semibold">#${b.bus_id}</td>
                <td class="font-mono font-bold text-white">${b.registration_number}</td>
                <td><span class="text-xs bg-slate-800 border border-slate-700 px-2 py-0.5 rounded text-slate-300">${b.bus_type}</span></td>
                <td class="text-slate-300">${b.manufacturer || ''} ${b.model || ''}</td>
                <td class="text-slate-300 font-mono">${b.seating_capacity} Sit / ${b.standing_capacity} Stand (${b.total_capacity})</td>
                <td><span class="badge badge-${b.status.toLowerCase()}">${b.status}</span></td>
                <td class="text-xs text-slate-400 font-mono">${b.last_service_date || 'None'}</td>
                <td>
                    <button onclick="inspectBusUtilization(${b.bus_id})" class="text-xs text-indigo-400 hover:text-indigo-300 font-medium">Metrics &rarr;</button>
                </td>
            </tr>
        `).join('');

        // Render Maintenance
        const maintTbody = document.getElementById('fleet-maintenance-tbody');
        maintTbody.innerHTML = maints.map(m => `
            <tr>
                <td class="font-mono text-slate-400">#${m.maintenance_id}</td>
                <td class="font-mono font-bold text-white">${m.registration_number}</td>
                <td class="text-slate-200">${m.maintenance_type}</td>
                <td class="text-xs font-mono text-slate-400">${m.maintenance_date}</td>
                <td class="text-xs font-mono text-slate-400">${m.next_service_date || 'N/A'}</td>
                <td class="font-mono text-emerald-400 font-bold">Rs ${m.maintenance_cost}</td>
                <td><span class="badge badge-${m.maintenance_status.toLowerCase()}">${m.maintenance_status}</span></td>
                <td>
                    ${m.maintenance_status !== 'COMPLETED' ? `
                        <button onclick="handleCompleteMaintenance(${m.maintenance_id})" class="bg-emerald-600/20 border border-emerald-500/30 hover:bg-emerald-600/40 text-emerald-300 px-2.5 py-1 rounded text-xs font-medium transition">
                            Complete
                        </button>
                    ` : '<span class="text-xs text-slate-500">Synced</span>'}
                </td>
            </tr>
        `).join('');

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load fleet data", "error");
    }
}

async function handleCompleteMaintenance(id) {
    try {
        const res = await fetch(`${API_BASE}/api/fleet/maintenance/${id}/complete`, { method: 'POST' });
        const data = await res.json();
        if (res.ok) {
            showToast("Maintenance completed! Last service date synchronized by trigger.", "success");
            loadFleetTab();
        } else {
            showToast(data.detail || "Completion failed", "error");
        }
    } catch (e) {
        showToast("Error updating maintenance", "error");
    }
}

async function inspectBusUtilization(busId) {
    try {
        const res = await fetch(`${API_BASE}/api/fleet/buses/${busId}/utilization`);
        const data = await res.json();
        viewJsonDelta(data, `Bus #${busId} Utilization (fn_get_bus_utilization)`);
    } catch (e) {
        showToast("Failed to fetch bus utilization", "error");
    }
}


// ---------------------------------------------------------------------
// 3. ROUTES & LIVE MAP TAB LOADER
// ---------------------------------------------------------------------
async function loadRoutesTab() {
    try {
        const [routesRes, stopsRes] = await Promise.all([
            fetch(`${API_BASE}/api/routes/views/performance`),
            fetch(`${API_BASE}/api/routes/stops/all`)
        ]);
        const routes = await routesRes.json();
        const stops = await stopsRes.json();

        // Render Routes Table
        const tbody = document.getElementById('routes-tbody');
        tbody.innerHTML = routes.map(r => `
            <tr>
                <td class="font-bold text-indigo-400 font-mono">${r.route_number}</td>
                <td class="font-semibold text-white">${r.route_name}</td>
                <td class="text-xs text-slate-300">${r.start_location}</td>
                <td class="text-xs text-slate-300">${r.end_location}</td>
                <td class="font-mono text-xs text-slate-400">${r.total_distance_km} km</td>
                <td class="font-mono text-slate-200">${r.total_scheduled_trips}</td>
                <td class="font-mono text-emerald-400">${r.completed_trips}</td>
                <td class="font-mono font-bold text-indigo-300">${r.completion_rate_pct}%</td>
            </tr>
        `).join('');

        // Initialize Map
        setTimeout(() => {
            initLeafletMap(stops);
        }, 150);

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load routes", "error");
    }
}

function initLeafletMap(stops) {
    const mapContainer = document.getElementById('transit-map');
    if (!mapContainer) return;

    if (!leafletMap) {
        leafletMap = L.map('transit-map').setView([12.9716, 77.5946], 12);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '&copy; OpenStreetMap contributors',
            maxZoom: 18
        }).addTo(leafletMap);
    }

    // Clear existing markers
    mapMarkers.forEach(m => leafletMap.removeLayer(m));
    mapMarkers = [];

    const bounds = [];
    stops.forEach(s => {
        if (s.latitude && s.longitude) {
            const latLng = [parseFloat(s.latitude), parseFloat(s.longitude)];
            bounds.push(latLng);

            const marker = L.circleMarker(latLng, {
                radius: 6,
                fillColor: '#6366f1',
                color: '#ffffff',
                weight: 2,
                opacity: 1,
                fillOpacity: 0.9
            }).addTo(leafletMap);

            marker.bindPopup(`
                <div style="font-family: sans-serif; color: #1e293b; padding: 2px;">
                    <strong style="font-size: 13px;">${s.stop_name}</strong><br/>
                    <span style="font-size: 11px; color: #64748b;">${s.location_description || 'Transit Stop'}</span><br/>
                    <code style="font-size: 10px; color: #4338ca;">Lat: ${s.latitude}, Lon: ${s.longitude}</code>
                </div>
            `);
            mapMarkers.push(marker);
        }
    });

    if (bounds.length > 0) {
        leafletMap.fitBounds(bounds, { padding: [30, 30] });
    }
    leafletMap.invalidateSize();
}


// ---------------------------------------------------------------------
// 4. TRIPS TAB LOADER
// ---------------------------------------------------------------------
async function loadTripsTab() {
    try {
        const res = await fetch(`${API_BASE}/api/trips?limit=100`);
        const trips = await res.json();
        const tbody = document.getElementById('trips-tbody');

        tbody.innerHTML = trips.map(t => `
            <tr>
                <td class="font-mono text-indigo-400 font-semibold">#${t.trip_id}</td>
                <td>
                    <span class="font-bold text-white">${t.route_number}</span>
                    <span class="text-xs text-slate-500 block truncate max-w-[140px]">${t.route_name}</span>
                </td>
                <td class="font-mono text-slate-200">${t.registration_number}</td>
                <td class="text-slate-300">${t.driver_name}</td>
                <td class="font-mono text-xs text-slate-400">${t.service_date}</td>
                <td class="font-mono text-xs text-slate-300">${new Date(t.scheduled_start).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</td>
                <td><span class="badge badge-${t.trip_status.toLowerCase()}">${t.trip_status}</span></td>
                <td>
                    <select onchange="updateTripStatus(${t.trip_id}, this.value)" class="bg-slate-900 border border-slate-700 text-slate-300 text-[11px] rounded px-2 py-1 focus:outline-none">
                        <option value="">Status...</option>
                        <option value="RUNNING">Set RUNNING</option>
                        <option value="COMPLETED">Set COMPLETED</option>
                        <option value="CANCELLED">Set CANCELLED</option>
                    </select>
                </td>
            </tr>
        `).join('');

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load trips", "error");
    }
}

async function updateTripStatus(tripId, newStatus) {
    if (!newStatus) return;
    try {
        const res = await fetch(`${API_BASE}/api/trips/${tripId}/status`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ trip_status: newStatus })
        });
        const data = await res.json();
        if (res.ok) {
            showToast(`Trip #${tripId} updated to ${newStatus}`, "success");
            loadTripsTab();
        } else {
            showToast(data.detail || "Status update failed", "error");
        }
    } catch (e) {
        showToast("Error updating trip status", "error");
    }
}


// ---------------------------------------------------------------------
// 5. PASSENGER DEMAND TAB LOADER
// ---------------------------------------------------------------------
async function loadPassengersTab() {
    try {
        const res = await fetch(`${API_BASE}/api/passengers/demand`);
        const demand = await res.json();
        const tbody = document.getElementById('passengers-demand-tbody');

        tbody.innerHTML = demand.map(d => `
            <tr>
                <td class="font-bold text-indigo-400 font-mono">${d.route_number}</td>
                <td class="text-white font-medium">${d.stop_name}</td>
                <td class="font-mono text-xs text-slate-400 text-center">${d.stop_sequence}</td>
                <td class="font-mono text-slate-300">${d.total_scheduled_visits}</td>
                <td class="font-mono text-emerald-400 font-semibold">${d.total_boardings}</td>
                <td class="font-mono text-blue-400 font-semibold">${d.total_alightings}</td>
                <td class="font-mono text-amber-400 font-bold">${d.total_footfall}</td>
                <td class="font-mono text-xs text-slate-400">${d.avg_boardings_per_visit}</td>
            </tr>
        `).join('');

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load passenger telemetry", "error");
    }
}


// ---------------------------------------------------------------------
// 6. DELAYS TAB LOADER
// ---------------------------------------------------------------------
async function loadDelaysTab() {
    try {
        const res = await fetch(`${API_BASE}/api/delays/analysis`);
        const delays = await res.json();
        const tbody = document.getElementById('delays-tbody');

        tbody.innerHTML = delays.map(d => `
            <tr>
                <td class="font-mono text-slate-400">#${d.delay_id}</td>
                <td class="font-mono text-xs text-slate-400">${d.service_date}</td>
                <td class="font-mono text-indigo-400 font-semibold">#${d.trip_id}</td>
                <td class="font-bold text-white font-mono">${d.route_number}</td>
                <td class="text-slate-300">${d.stop_name}</td>
                <td class="text-amber-300 font-medium">${d.reason_name}</td>
                <td class="font-mono text-slate-200 font-bold">${d.delay_seconds}s</td>
                <td><span class="badge badge-${d.severity.toLowerCase()}">${d.severity}</span></td>
                <td class="text-xs text-slate-400 italic">${d.remarks || 'None'}</td>
            </tr>
        `).join('');

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load delay analysis", "error");
    }
}


// ---------------------------------------------------------------------
// 7. DRIVERS TAB LOADER
// ---------------------------------------------------------------------
async function loadDriversTab() {
    try {
        const res = await fetch(`${API_BASE}/api/drivers`);
        const drivers = await res.json();
        const tbody = document.getElementById('drivers-tbody');

        tbody.innerHTML = drivers.map(d => `
            <tr>
                <td class="font-mono text-indigo-400 font-semibold">${d.employee_code}</td>
                <td class="font-semibold text-white">${d.full_name}</td>
                <td class="font-mono text-xs text-slate-300">${d.phone_number || 'N/A'}</td>
                <td class="font-mono text-xs text-slate-400">${d.license_number}</td>
                <td class="font-mono text-xs text-slate-400">${d.license_expiry_date}</td>
                <td><span class="badge badge-${d.license_status.toLowerCase()}">${d.license_status}</span></td>
                <td><span class="badge badge-${d.status.toLowerCase()}">${d.status}</span></td>
                <td>
                    <button onclick="inspectDriverPerformance(${d.driver_id})" class="text-xs text-indigo-400 hover:text-indigo-300 font-medium">Audit &rarr;</button>
                </td>
            </tr>
        `).join('');

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load driver roster", "error");
    }
}

async function inspectDriverPerformance(driverId) {
    try {
        const res = await fetch(`${API_BASE}/api/drivers/${driverId}/performance-function`);
        const data = await res.json();
        viewJsonDelta(data, `Driver #${driverId} Performance Audit (fn_get_driver_performance)`);
    } catch (e) {
        showToast("Failed to audit driver performance", "error");
    }
}


// ---------------------------------------------------------------------
// 8. AUDIT LOG TAB LOADER
// ---------------------------------------------------------------------
async function loadAuditTab() {
    try {
        const res = await fetch(`${API_BASE}/api/audit/logs?limit=50`);
        const logs = await res.json();
        const tbody = document.getElementById('audit-tbody');

        tbody.innerHTML = logs.map(l => `
            <tr>
                <td class="font-mono text-slate-400">#${l.audit_id}</td>
                <td class="font-mono text-indigo-400 font-bold">${l.table_name}</td>
                <td class="font-mono text-slate-300">${l.record_id || 'N/A'}</td>
                <td>
                    <span class="badge ${l.operation === 'INSERT' ? 'badge-active' : l.operation === 'UPDATE' ? 'badge-running' : 'badge-severe'}">${l.operation}</span>
                </td>
                <td class="font-mono text-xs text-slate-400">${l.changed_by}</td>
                <td class="font-mono text-xs text-slate-400">${new Date(l.changed_at).toLocaleString()}</td>
                <td>
                    <button onclick='viewJsonDelta(${JSON.stringify(l.new_data || l.old_data || {})}, "Audit #${l.audit_id} (${l.table_name} ${l.operation})")' class="text-xs text-indigo-400 hover:underline font-mono">
                        View JSON &rarr;
                    </button>
                </td>
            </tr>
        `).join('');

        lucide.createIcons();
    } catch (e) {
        showToast("Failed to load audit logs", "error");
    }
}


// ---------------------------------------------------------------------
// MODALS & FORM ACTIONS
// ---------------------------------------------------------------------
function openModal(modalId) {
    document.getElementById(modalId)?.classList.remove('hidden');
    lucide.createIcons();
}

function closeModal(modalId) {
    document.getElementById(modalId)?.classList.add('hidden');
}

function viewJsonDelta(obj, title = "Data Inspector") {
    document.getElementById('json-modal-title').textContent = title;
    document.getElementById('json-modal-content').textContent = JSON.stringify(obj, null, 2);
    openModal('modal-json');
}

async function initModalsData() {
    try {
        // Populate schedules dropdown
        const schedRes = await fetch(`${API_BASE}/api/routes/schedules/all`);
        const scheds = await schedRes.json();
        const schedSelect = document.getElementById('dispatch-schedule-select');
        schedSelect.innerHTML = '<option value="">Select Schedule...</option>' + 
            scheds.map(s => `<option value="${s.schedule_id}" data-route="${s.route_id}">${s.route_number} - ${s.schedule_name} (${s.departure_time})</option>`).join('');

        // Populate buses dropdown
        const busRes = await fetch(`${API_BASE}/api/fleet/buses?status=ACTIVE`);
        const buses = await busRes.json();
        const busSelect = document.getElementById('dispatch-bus-select');
        busSelect.innerHTML = '<option value="">Select Bus...</option>' + 
            buses.map(b => `<option value="${b.bus_id}">${b.registration_number} (${b.bus_type})</option>`).join('');

        // Populate drivers dropdown
        const driverRes = await fetch(`${API_BASE}/api/drivers?status=AVAILABLE`);
        const drivers = await driverRes.json();
        const driverSelect = document.getElementById('dispatch-driver-select');
        driverSelect.innerHTML = '<option value="">Select Driver...</option>' + 
            drivers.map(d => `<option value="${d.driver_id}">${d.full_name} (${d.employee_code})</option>`).join('');

        // Populate delay reasons dropdown
        const reasonRes = await fetch(`${API_BASE}/api/delays/reasons`);
        const reasons = await reasonRes.json();
        const reasonSelect = document.getElementById('delay-reason-select');
        reasonSelect.innerHTML = '<option value="">Select Reason...</option>' + 
            reasons.map(r => `<option value="${r.reason_id}">${r.reason_name}</option>`).join('');

        // Set default date to today
        document.getElementById('dispatch-service-date').valueAsDate = new Date();
        document.getElementById('dispatch-start-time').value = new Date().toTimeString().substring(0, 5);
    } catch (e) {
        console.error("Modal init error:", e);
    }
}

function openDispatchModal() {
    initModalsData();
    openModal('modal-dispatch');
}

function openDelayModal() {
    initModalsData();
    openModal('modal-delay');
}

function openPassengerModal() {
    openModal('modal-passenger');
}

async function handleDispatchTrip(e) {
    e.preventDefault();
    const schedSelect = document.getElementById('dispatch-schedule-select');
    const selectedOption = schedSelect.options[schedSelect.selectedIndex];
    const routeId = selectedOption?.getAttribute('data-route');

    const payload = {
        schedule_id: parseInt(schedSelect.value),
        route_id: parseInt(routeId),
        bus_id: parseInt(document.getElementById('dispatch-bus-select').value),
        driver_id: parseInt(document.getElementById('dispatch-driver-select').value),
        service_date: document.getElementById('dispatch-service-date').value,
        scheduled_start: `${document.getElementById('dispatch-service-date').value}T${document.getElementById('dispatch-start-time').value}:00`
    };

    try {
        const res = await fetch(`${API_BASE}/api/trips`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (res.ok) {
            showToast(`Trip #${data.trip_id} dispatched successfully! (sp_create_trip)`, "success");
            closeModal('modal-dispatch');
            if (currentTab === 'trips') loadTripsTab();
            else loadDashboard();
        } else {
            showToast(data.detail || "Dispatch validation failed", "error");
        }
    } catch (err) {
        showToast("Error executing dispatch procedure", "error");
    }
}

async function handleRecordDelay(e) {
    e.preventDefault();
    const payload = {
        trip_stop_log_id: parseInt(document.getElementById('delay-stop-log-id').value),
        reason_id: parseInt(document.getElementById('delay-reason-select').value),
        delay_seconds: parseInt(document.getElementById('delay-seconds-input').value),
        remarks: document.getElementById('delay-remarks-input').value
    };

    try {
        const res = await fetch(`${API_BASE}/api/delays/record`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (res.ok) {
            showToast(`Delay recorded! Severity: ${data.delay.severity}`, "success");
            closeModal('modal-delay');
            if (currentTab === 'delays') loadDelaysTab();
            else loadDashboard();
        } else {
            showToast(data.detail || "Delay recording failed", "error");
        }
    } catch (err) {
        showToast("Error recording delay", "error");
    }
}

async function handleRecordPassenger(e) {
    e.preventDefault();
    const payload = {
        trip_stop_log_id: parseInt(document.getElementById('pass-stop-log-id').value),
        boarding_count: parseInt(document.getElementById('pass-boarding-input').value),
        alighting_count: parseInt(document.getElementById('pass-alighting-input').value)
    };

    try {
        const res = await fetch(`${API_BASE}/api/passengers/record`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (res.ok) {
            showToast("Passenger footfall recorded! (sp_record_passenger_count)", "success");
            closeModal('modal-passenger');
            if (currentTab === 'passengers') loadPassengersTab();
            else loadDashboard();
        } else {
            showToast(data.detail || "Recording failed", "error");
        }
    } catch (err) {
        showToast("Error recording passenger count", "error");
    }
}
