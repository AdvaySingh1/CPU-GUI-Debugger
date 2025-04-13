<script lang="ts">
    import { onMount } from 'svelte';

    type FileData = {
        name: string;
        content: string;
    };

    type ComponentData = {
        name: string;
        content: string;
    };

    type CycleData = {
        cycle: number;
        components: ComponentData[];
    };

    type Position = {
        x: number;
        y: number;
    };

    type RetireSignalInfo = {
        lastActiveCycle: number;
        index: number;
    };

    type DispatchInfo = {
        lastActiveCycle: number;
        pattern: string;
    };

    let files: FileData[] = [];
    let error: string | null = null;
    let selectedFile: FileData | null = null;
    let cycles: CycleData[] = [];
    let currentCycleIndex = 0;
    let expandedComponents = new Set<string>();
    let componentPositions = new Map<string, Position>();
    let searchCycle = '';
    let searchPC = '';
    let searchError: string | null = null;
    let isDragging = false;
    let retireSignals: RetireSignalInfo[] = [];
    let lastDispatchActive: DispatchInfo | null = null;
    let foundPCEntry: string | null = null;

    function getDisplayFileName(fullName: string): string {
        return fullName.replace('_svelte', '');
    }

    onMount(async () => {
        try {
            const response = await fetch('/api/files');
            if (!response.ok) throw new Error('Failed to fetch files');
            files = await response.json();
        } catch (e) {
            error = String(e);
        }
    });

    function parseComponents(content: string): ComponentData[] {
        const componentRegex = /\*\*\* (.+?)\n([\s\S]*?)(?=\*\*\* |$)/g;
        const components: ComponentData[] = [];
        let match;

        while ((match = componentRegex.exec(content))) {
            components.push({
                name: match[1].trim(),
                content: match[2].trim()
            });
        }

        return components;
    }

    function parseCycles(content: string): CycleData[] {
        const cycleRegex = /\$\$\$ (\d+)\n([\s\S]*?)(?=\$\$\$ \d+|$)/g;
        const cycles: CycleData[] = [];
        let match;

        while ((match = cycleRegex.exec(content)) !== null) {
            cycles.push({
                cycle: parseInt(match[1]),
                components: parseComponents(match[2])
            });
        }

        return cycles;
    }

    function viewFile(file: FileData) {
        selectedFile = file;
        cycles = parseCycles(file.content);
        currentCycleIndex = 0;
        expandedComponents.clear();
        searchPC = '';
        foundPCEntry = null;
        analyzeRetireSignals();
    }

    function analyzeRetireSignals() {
        retireSignals = [];
        lastDispatchActive = null;
        const robEntryMap = new Map<number, number>(); // Map of entry index to last active cycle

        // Process each cycle
        for (const cycle of cycles) {
            // Find the ROB Signals component
            const robComponent = cycle.components.find(comp => comp.name.includes('ROB Signals'));
            if (robComponent) {
                // Parse the content to find En[x] signals
                const lines = robComponent.content.split('\n');
                for (const line of lines) {
                    const match = line.match(/En\[(\d+)\]:\s*(\d+)/);
                    if (match) {
                        const entryIndex = parseInt(match[1]);
                        const isEnabled = match[2] === '1';

                        // If enabled, update the last active cycle for this entry
                        if (isEnabled) {
                            robEntryMap.set(entryIndex, cycle.cycle);
                        }
                    }
                }
            }

            // Find the Dispatch component
            const dispatchComponent = cycle.components.find(comp => comp.name.includes('Dispatch'));
            if (dispatchComponent) {
                // Parse the content to find En: signal
                const lines = dispatchComponent.content.split('\n');
                for (const line of lines) {
                    const match = line.match(/En:\s*([01]+)/);
                    if (match) {
                        const pattern = match[1];
                        // Check if at least one bit is high
                        if (pattern.includes('1')) {
                            lastDispatchActive = {
                                lastActiveCycle: cycle.cycle,
                                pattern: pattern
                            };
                        }
                    }
                }
            }
        }

        // Convert the map to our result array
        robEntryMap.forEach((lastCycle, index) => {
            retireSignals.push({
                index,
                lastActiveCycle: lastCycle
            });
        });

        // Sort by entry index
        retireSignals.sort((a, b) => a.index - b.index);
    }

    function nextCycle() {
        if (currentCycleIndex < cycles.length - 1) {
            currentCycleIndex++;
            // Removed expandedComponents.clear()
        }
    }

    function prevCycle() {
        if (currentCycleIndex > 0) {
            currentCycleIndex--;
            // Removed expandedComponents.clear()
        }
    }

    function toggleComponent(componentName: string) {
        if (expandedComponents.has(componentName)) {
            expandedComponents.delete(componentName);
        } else {
            expandedComponents.add(componentName);
        }
        expandedComponents = expandedComponents; // trigger reactivity
    }

    function searchByCycle() {
        const cycleNum = parseInt(searchCycle);
        if (isNaN(cycleNum)) {
            searchError = 'Please enter a valid number';
            return;
        }

        const foundIndex = cycles.findIndex(c => c.cycle === cycleNum);
        if (foundIndex === -1) {
            searchError = `Cycle ${cycleNum} not found`;
            return;
        }

        searchError = null;
        currentCycleIndex = foundIndex;
    }

    function searchByPC() {
        if (!searchPC.trim()) {
            searchError = 'Please enter a PC value';
            return;
        }

        // Reset the found PC entry
        foundPCEntry = null;

        // Normalize the PC value (remove leading zeros)
        const normalizedPC = searchPC.replace(/^0+/, '');

        // Search through all cycles
        for (let i = 0; i < cycles.length; i++) {
            const cycle = cycles[i];
            // Find the Dispatch component
            const dispatchComponent = cycle.components.find(comp => comp.name.includes('Dispatch'));
            if (!dispatchComponent) continue;

            // Parse the content to find PC values
            const content = dispatchComponent.content;
            const rsEntryMatches = [...content.matchAll(/RS_ENTRY\s*\[(\d+)\][\s\S]*?PC:\s*([0-9a-fA-F]+)/g)];

            // Check each PC value
            for (const match of rsEntryMatches) {
                const entryIndex = match[1];
                // Get the PC value and normalize it (remove leading zeros)
                const pcValue = match[2].replace(/^0+/, '');

                // If we found a match
                if (pcValue === normalizedPC) {
                    searchError = null;
                    currentCycleIndex = i;
                    foundPCEntry = `RS_ENTRY[${entryIndex}]`;
                    // Ensure the Dispatch component is expanded
                    expandedComponents.add('Dispatch');
                    return;
                }
            }
        }

        // If we get here, no match was found
        searchError = `PC ${searchPC} not found in any dispatch entry`;
    }

    function startDrag(event: MouseEvent, componentName: string) {
        // Prevent default to avoid text selection during drag
        event.preventDefault();

        // Stop event propagation to prevent conflicts with other handlers
        event.stopPropagation();

        isDragging = true;
        const componentElement = document.querySelector(`[data-component="${componentName}"]`) as HTMLElement;
        if (!componentElement) return;

        // Store the initial mouse position and the component's current position
        const initialX = event.clientX;
        const initialY = event.clientY;

        // Get current position or default to the current layout position
        const currentPos = componentPositions.get(componentName) || {
            x: componentElement.offsetLeft,
            y: componentElement.offsetTop
        };

        // Create the mousemove event handler
        const handleMouseMove = (moveEvent: MouseEvent) => {
            if (!isDragging) return;

            // Calculate the new position
            const newX = currentPos.x + (moveEvent.clientX - initialX);
            const newY = currentPos.y + (moveEvent.clientY - initialY);

            // Update the component's position
            componentElement.style.position = 'absolute';
            componentElement.style.left = `${newX}px`;
            componentElement.style.top = `${newY}px`;
            componentElement.style.zIndex = '10';

            // Store the new position
            componentPositions.set(componentName, { x: newX, y: newY });
        };

        // Create the mouseup event handler
        const handleMouseUp = () => {
            isDragging = false;
            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);
        };

        // Add the event listeners
        document.addEventListener('mousemove', handleMouseMove);
        document.addEventListener('mouseup', handleMouseUp);
    }
</script>

<div class="p-2 bg-gray-50">
    <h1 class="text-2xl font-bold mb-2 text-gray-800">470 GUI Debugger</h1>

    {#if error}
        <div class="text-red-500 text-sm">Error: {error}</div>
    {/if}

    {#if !selectedFile}
        <div class="grid grid-cols-4 gap-2">
            {#each files as file}
                <button
                    type="button"
                    class="border rounded p-2 cursor-pointer hover:bg-gray-200 bg-white shadow-sm text-left"
                    on:click={() => viewFile(file)}
                    on:keydown={(e) => e.key === 'Enter' && viewFile(file)}
                >
                    <h2 class="text-base font-semibold text-gray-700">{getDisplayFileName(file.name)}</h2>
                </button>
            {/each}
        </div>
    {:else}
        <div class="mb-2 flex items-center gap-2">
            <button
                class="bg-gray-700 text-white px-2 py-1 rounded text-sm hover:bg-gray-600"
                on:click={() => selectedFile = null}
            >
                Back to Files
            </button>
            <h2 class="text-lg font-semibold text-gray-700">{getDisplayFileName(selectedFile.name)}</h2>
        </div>

        <div class="border rounded p-2 bg-white shadow-sm">
            <div class="flex items-center justify-between mb-2">
                <div class="flex gap-2 items-center">
                    <div class="flex items-center gap-2">
                        <div class="flex items-center gap-1">
                            <input
                                type="number"
                                bind:value={searchCycle}
                                placeholder="Search cycle..."
                                class="px-1 py-0.5 border rounded w-24 text-sm focus:outline-none focus:ring-1 focus:ring-gray-400"
                                on:keydown={(e) => e.key === 'Enter' && searchByCycle()}
                            />
                            <button
                                class="bg-gray-700 text-white px-2 py-0.5 rounded text-sm hover:bg-gray-600"
                                on:click={searchByCycle}
                            >
                                Go
                            </button>
                        </div>

                        <div class="flex items-center gap-1">
                            <input
                                type="text"
                                bind:value={searchPC}
                                placeholder="Search PC..."
                                class="px-1 py-0.5 border rounded w-24 text-sm focus:outline-none focus:ring-1 focus:ring-gray-400"
                                on:keydown={(e) => e.key === 'Enter' && searchByPC()}
                                on:input={() => { if (!searchPC) foundPCEntry = null; }}
                            />
                            <button
                                class="bg-green-700 text-white px-2 py-0.5 rounded text-sm hover:bg-green-600"
                                on:click={searchByPC}
                            >
                                Find PC
                            </button>
                        </div>
                    </div>
                    <button
                        class="bg-gray-200 px-2 py-0.5 rounded text-sm {currentCycleIndex === 0 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-300'}"
                        on:click={prevCycle}
                        disabled={currentCycleIndex === 0}
                    >
                        &lt;
                    </button>
                    <span class="text-gray-700 text-sm">Cycle {cycles[currentCycleIndex]?.cycle}</span>
                    <button
                        class="bg-gray-200 px-2 py-0.5 rounded text-sm {currentCycleIndex === cycles.length - 1 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-300'}"
                        on:click={nextCycle}
                        disabled={currentCycleIndex === cycles.length - 1}
                    >
                        &gt;
                    </button>
                </div>
            </div>

            {#if searchError}
                <div class="text-red-500 text-xs mb-2">{searchError}</div>
            {/if}

            <div class="relative min-h-[500px]">
                {#each cycles[currentCycleIndex]?.components || [] as component}
                    <div
                        class="mb-2 inline-block component-container"
                        style="{componentPositions.has(component.name) ? `position: absolute; left: ${componentPositions.get(component.name)?.x}px; top: ${componentPositions.get(component.name)?.y}px; z-index: ${expandedComponents.has(component.name) ? '10' : '1'};` : ''}"
                        data-component={component.name}
                        role="region"
                        aria-label={`Component ${component.name}`}
                    >
                        <div
                            class="{expandedComponents.has(component.name)
                                ? component.name.toLowerCase().includes('free list')
                                    ? 'w-[280px]'
                                    : 'min-w-[300px] max-w-[800px]'
                                : 'w-[200px]'}
                            border rounded overflow-hidden transition-all duration-200 bg-white shadow-sm"
                        >
                            <button
                                type="button"
                                class="component-header bg-gray-100 p-1 cursor-move hover:bg-gray-200 flex justify-between items-center w-full text-left"
                                on:click={() => toggleComponent(component.name)}
                                on:keydown={(e) => e.key === 'Enter' && toggleComponent(component.name)}
                                on:mousedown={(e) => startDrag(e, component.name)}
                            >
                                <h3 class="font-semibold text-gray-700 text-xs px-1">{component.name}</h3>
                                <span class="text-gray-600 text-xs px-1">
                                    {expandedComponents.has(component.name) ? '▼' : '▶'}
                                </span>
                            </button>
                            {#if expandedComponents.has(component.name)}
                                <pre class="p-1 bg-white whitespace-pre-wrap text-xs overflow-x-auto">
                                    <code>{component.content}</code>
                                </pre>

                                {#if component.name.includes('ROB Signals') && retireSignals.length > 0}
                                    <div class="p-2 bg-blue-50 border-t border-blue-200">
                                        <h4 class="font-semibold text-xs text-blue-700 mb-1">Last Active Retire Signals:</h4>
                                        <div class="grid grid-cols-3 gap-1 text-xs">
                                            {#each retireSignals as signal}
                                                <div class="bg-blue-100 p-1 rounded">
                                                    Entry[{signal.index}]: Cycle {signal.lastActiveCycle}
                                                </div>
                                            {/each}
                                        </div>
                                    </div>
                                {/if}

                                {#if component.name.includes('Dispatch')}
                                    <div class="p-2 bg-green-50 border-t border-green-200">
                                        {#if lastDispatchActive}
                                            <h4 class="font-semibold text-xs text-green-700 mb-1">Last Active Dispatch Signal:</h4>
                                            <div class="bg-green-100 p-1 rounded text-xs mb-2">
                                                Cycle {lastDispatchActive.lastActiveCycle}: En: {lastDispatchActive.pattern}
                                            </div>
                                        {/if}

                                        {#if foundPCEntry}
                                            <h4 class="font-semibold text-xs text-green-700 mb-1">Found PC Match:</h4>
                                            <div class="bg-yellow-100 p-1 rounded text-xs border border-yellow-300">
                                                Entry: {foundPCEntry} - PC: {searchPC}
                                            </div>
                                        {/if}
                                    </div>
                                {/if}
                            {/if}
                        </div>
                    </div>
                {/each}
            </div>
        </div>
    {/if}

    {#if files.length === 0 && !error}
        <div class="text-gray-500 text-sm">No files found in the directory</div>
    {/if}
</div>
