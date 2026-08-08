const app = document.getElementById('app');
const brandName = document.getElementById('brand-name');
const tagline = document.getElementById('tagline');
const garageLabel = document.getElementById('garage-label');
const garageKind = document.getElementById('garage-kind');
const garageDescription = document.getElementById('garage-description');
const sideKind = document.getElementById('side-kind');
const sideCategory = document.getElementById('side-category');
const totalCount = document.getElementById('total-count');
const readyCount = document.getElementById('ready-count');
const searchInput = document.getElementById('search-input');
const vehicleList = document.getElementById('vehicle-list');
const details = document.getElementById('vehicle-details');
const emptyState = document.getElementById('empty-state');
const closeButton = document.getElementById('close-button');
const retrieveButton = document.getElementById('retrieve-button');
const retrieveLabel = document.getElementById('retrieve-label');
const feeCard = document.getElementById('fee-card');
const feeValue = document.getElementById('fee-value');
const holdCard = document.getElementById('hold-card');
const holdMessage = document.getElementById('hold-message');
const vehicleStatus = document.getElementById('vehicle-status');
const vehicleCategory = document.getElementById('vehicle-category');
const vehicleBrand = document.getElementById('vehicle-brand');
const vehicleName = document.getElementById('vehicle-name');
const vehiclePlate = document.getElementById('vehicle-plate');
const carArt = document.getElementById('car-art');

let garage = null;
let vehicles = [];
let selectedId = null;
let activeFilter = 'all';
let resourceName = 'qbx_garages';

const currency = new Intl.NumberFormat('en-GB', {
    style: 'currency',
    currency: 'GBP',
    maximumFractionDigits: 0,
});

function post(endpoint, payload = {}) {
    return fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).then((response) => response.json()).catch(() => ({ ok: false }));
}

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

function carSvg(large = false) {
    const id = large ? 'lg' : `sm-${Math.random().toString(36).slice(2)}`;
    return `
        <svg viewBox="0 0 620 250" aria-hidden="true">
            <defs>
                <linearGradient id="body-${id}" x1="0" y1="0" x2="1" y2="1">
                    <stop offset="0" stop-color="#d9a6be"/>
                    <stop offset=".45" stop-color="#b7608c"/>
                    <stop offset="1" stop-color="#76445d"/>
                </linearGradient>
                <linearGradient id="glass-${id}" x1="0" y1="0" x2="1" y2="1">
                    <stop offset="0" stop-color="#fff7fb" stop-opacity=".82"/>
                    <stop offset="1" stop-color="#34232c" stop-opacity=".92"/>
                </linearGradient>
            </defs>
            <path fill="url(#body-${id})" d="M73 154c8-28 31-47 70-54l96-17c30-36 64-54 116-55h61c48 1 87 20 119 57l33 10c23 7 38 26 41 52l2 24-41 8H98l-32-11 7-14Z"/>
            <path fill="#593144" d="M223 92c34-37 69-47 126-48h63c39 1 67 13 99 44l-288 4Z"/>
            <path fill="url(#glass-${id})" d="M249 84c29-23 58-31 104-32h52c30 1 54 9 80 31l-236 1Z"/>
            <path fill="#dfb1c6" d="M80 147c102 8 188 11 303 7 80-3 142-11 201-25l8 18c-38 16-86 27-149 33H113c-22-2-36-11-33-33Z"/>
            <path fill="#39232d" d="M465 157h112l-17 23h-96l1-23ZM92 157h87l6 23h-80l-13-23Z"/>
            <circle cx="181" cy="179" r="43" fill="#2a1821"/>
            <circle cx="181" cy="179" r="26" fill="#e5d6dd"/>
            <circle cx="181" cy="179" r="12" fill="#8b6075"/>
            <circle cx="482" cy="179" r="43" fill="#2a1821"/>
            <circle cx="482" cy="179" r="26" fill="#e5d6dd"/>
            <circle cx="482" cy="179" r="12" fill="#8b6075"/>
            <path fill="#f7eef3" d="M104 127h42l17 10-63 2 4-12Zm412-19 41 11-5 17-48-5 12-23Z"/>
            <path fill="#664054" d="M304 93h7v54h-7z"/>
        </svg>`;
}

function getFilteredVehicles() {
    const query = searchInput.value.trim().toLowerCase();

    return vehicles.filter((vehicle) => {
        const searchable = `${vehicle.label} ${vehicle.plate} ${vehicle.modelName}`.toLowerCase();
        const matchesSearch = !query || searchable.includes(query);
        const matchesFilter = activeFilter === 'all'
            || (activeFilter === 'ready' && vehicle.canRetrieve)
            || (activeFilter === 'unavailable' && !vehicle.canRetrieve);
        return matchesSearch && matchesFilter;
    });
}

function renderVehicleList() {
    const filtered = getFilteredVehicles();
    vehicleList.innerHTML = '';

    if (!filtered.length) {
        details.classList.add('hidden');
        vehicleList.classList.add('hidden');
        emptyState.classList.remove('hidden');
        return;
    }

    emptyState.classList.add('hidden');
    vehicleList.classList.remove('hidden');
    details.classList.remove('hidden');

    if (!filtered.some((vehicle) => vehicle.id === selectedId)) {
        selectedId = filtered[0].id;
    }

    filtered.forEach((vehicle) => {
        const button = document.createElement('button');
        button.className = `vehicle-card ${vehicle.id === selectedId ? 'active' : ''}`;
        button.innerHTML = `
            <div class="vehicle-card-top">
                <span class="vehicle-card-copy">
                    <strong>${escapeHtml(vehicle.label)}</strong>
                    <small>${escapeHtml(vehicle.plate)}</small>
                </span>
                <span class="card-status ${escapeHtml(vehicle.statusKey)}">${escapeHtml(vehicle.status.toUpperCase())}</span>
            </div>
            <div class="card-car">${carSvg(false)}</div>
            <span class="card-category">${escapeHtml(vehicle.category || 'vehicle')}</span>
        `;
        button.addEventListener('click', () => {
            selectedId = vehicle.id;
            renderVehicleList();
            renderDetails();
        });
        vehicleList.appendChild(button);
    });

    renderDetails();
}

function setCondition(type, value) {
    const safeValue = Math.max(0, Math.min(100, Number(value) || 0));
    document.getElementById(`${type}-value`).textContent = `${safeValue}%`;
    document.getElementById(`${type}-bar`).style.width = `${safeValue}%`;
}

function renderDetails() {
    const vehicle = vehicles.find((item) => item.id === selectedId);
    if (!vehicle) return;

    vehicleStatus.textContent = vehicle.status.toUpperCase();
    vehicleStatus.className = `status-pill ${vehicle.statusKey}`;
    vehicleCategory.textContent = String(vehicle.category || 'vehicle').toUpperCase();
    vehicleBrand.textContent = String(vehicle.brand || 'CUSTOM').toUpperCase();
    vehicleName.textContent = vehicle.name || vehicle.modelName;
    vehiclePlate.textContent = vehicle.plate;
    carArt.innerHTML = carSvg(true);

    setCondition('body', vehicle.body);
    setCondition('engine', vehicle.engine);
    setCondition('fuel', vehicle.fuel);

    const isImpound = garage?.type === 'impound';
    feeCard.classList.toggle('hidden', !(isImpound && vehicle.canRetrieve));
    feeValue.textContent = currency.format(vehicle.depotPrice || 0);

    holdCard.classList.toggle('hidden', vehicle.canRetrieve);
    if (!vehicle.canRetrieve) {
        holdMessage.textContent = vehicle.statusKey === 'impounded'
            ? 'This vehicle is under authority hold and cannot be released.'
            : 'This vehicle is already outside of this garage.';
    }

    retrieveButton.disabled = !vehicle.canRetrieve;
    retrieveLabel.textContent = vehicle.canRetrieve ? vehicle.actionLabel : 'Vehicle Unavailable';
}

function openUi(data) {
    resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'qbx_garages';
    garage = data.garage;
    vehicles = data.vehicles || [];
    selectedId = vehicles[0]?.id ?? null;
    activeFilter = 'all';
    searchInput.value = '';

    brandName.textContent = data.brand || 'Pink Parking';
    tagline.textContent = data.tagline || 'Secure vehicle management';
    garageLabel.textContent = garage?.label || 'Vehicle Garage';
    garageKind.textContent = garage?.type === 'impound' ? 'IMPOUND' : 'GARAGE';
    sideKind.textContent = garage?.type === 'impound' ? 'Impound' : 'Garage';
    sideCategory.textContent = garage?.vehicleType || 'All';
    garageDescription.textContent = garage?.type === 'impound'
        ? 'Eligible vehicles can be released here after any applicable fee.'
        : 'Select a vehicle to view its condition and retrieval status.';

    totalCount.textContent = vehicles.length;
    readyCount.textContent = vehicles.filter((vehicle) => vehicle.canRetrieve).length;

    document.querySelectorAll('.filter-nav').forEach((button) => {
        button.classList.toggle('active', button.dataset.filter === 'all');
    });

    renderVehicleList();
    document.body.classList.add('nui-open');
    app.classList.remove('hidden');
    app.classList.add('nui-open');
    app.setAttribute('aria-hidden', 'false');
}

function closeUi() {
    document.body.classList.remove('nui-open');
    app.classList.remove('nui-open');
    app.classList.add('hidden');
    app.setAttribute('aria-hidden', 'true');
    garage = null;
    vehicles = [];
    selectedId = null;
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data?.action) return;

    if (data.action === 'open') openUi(data);
    if (data.action === 'close') closeUi();
});

closeButton.addEventListener('click', () => post('close'));
searchInput.addEventListener('input', renderVehicleList);

document.querySelectorAll('.filter-nav').forEach((button) => {
    button.addEventListener('click', () => {
        activeFilter = button.dataset.filter;
        document.querySelectorAll('.filter-nav').forEach((item) => item.classList.toggle('active', item === button));
        renderVehicleList();
    });
});

retrieveButton.addEventListener('click', async () => {
    const vehicle = vehicles.find((item) => item.id === selectedId);
    if (!vehicle?.canRetrieve) return;

    retrieveButton.disabled = true;
    retrieveLabel.textContent = garage?.type === 'impound' ? 'Releasing Vehicle...' : 'Preparing Vehicle...';
    const response = await post('retrieveVehicle', { id: vehicle.id });

    if (!response?.ok) {
        retrieveButton.disabled = false;
        renderDetails();
    }
});

document.addEventListener('keydown', (event) => {
    if (app.classList.contains('hidden')) return;
    if (event.key === 'Escape') post('close');
});

resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'qbx_garages';
closeUi();
post('ready');
