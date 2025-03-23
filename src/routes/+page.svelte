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

    let files: FileData[] = [];
    let error: string | null = null;
    let selectedFile: FileData | null = null;
    let cycles: CycleData[] = [];
    let currentCycleIndex = 0;
    let expandedComponents = new Set<string>();
    let searchCycle = '';
    let searchError: string | null = null;

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
</script>

<div class="p-4 bg-gray-50">
    <h1 class="text-3xl font-bold mb-4 text-gray-800">470 GUI Debugger</h1>
    
    {#if error}
        <div class="text-red-500">Error: {error}</div>
    {/if}

    {#if !selectedFile}
        <div class="grid grid-cols-3 gap-4">
            {#each files as file}
                <div 
                    class="border rounded-lg p-4 cursor-pointer hover:bg-gray-200 bg-white shadow-sm"
                    on:click={() => viewFile(file)}
                >
                    <h2 class="text-xl font-semibold text-gray-700">{getDisplayFileName(file.name)}</h2>
                </div>
            {/each}
        </div>
    {:else}
        <div class="mb-4 flex items-center gap-4">
            <button 
                class="bg-gray-700 text-white px-4 py-2 rounded hover:bg-gray-600"
                on:click={() => selectedFile = null}
            >
                Back to Files
            </button>
            <h2 class="text-2xl font-semibold text-gray-700">{getDisplayFileName(selectedFile.name)}</h2>
        </div>

        <div class="border rounded-lg p-4 bg-white shadow-sm">
            <div class="flex items-center justify-between mb-4">
                <div class="flex gap-4 items-center">
                    <div class="flex items-center gap-2">
                        <input
                            type="number"
                            bind:value={searchCycle}
                            placeholder="Search cycle..."
                            class="px-2 py-1 border rounded w-32 focus:outline-none focus:ring-2 focus:ring-gray-400"
                            on:keydown={(e) => e.key === 'Enter' && searchByCycle()}
                        />
                        <button
                            class="bg-gray-700 text-white px-3 py-1 rounded hover:bg-gray-600"
                            on:click={searchByCycle}
                        >
                            Go
                        </button>
                    </div>
                    <button 
                        class="bg-gray-200 px-4 py-2 rounded {currentCycleIndex === 0 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-300'}"
                        on:click={prevCycle}
                        disabled={currentCycleIndex === 0}
                    >
                        &lt;
                    </button>
                    <span class="text-gray-700">Cycle {cycles[currentCycleIndex]?.cycle}</span>
                    <button 
                        class="bg-gray-200 px-4 py-2 rounded {currentCycleIndex === cycles.length - 1 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-300'}"
                        on:click={nextCycle}
                        disabled={currentCycleIndex === cycles.length - 1}
                    >
                        &gt;
                    </button>
                </div>
            </div>

            {#if searchError}
                <div class="text-red-500 text-sm mb-4">{searchError}</div>
            {/if}

            <div class="grid grid-cols-3 gap-4">
                {#each cycles[currentCycleIndex]?.components || [] as component}
                    <div class="{expandedComponents.has(component.name) ? 'col-span-3' : 'col-span-1'} border rounded-lg overflow-hidden transition-all duration-200 bg-white shadow-sm">
                        <div 
                            class="bg-gray-100 p-3 cursor-pointer hover:bg-gray-200 flex justify-between items-center"
                            on:click={() => toggleComponent(component.name)}
                        >
                            <h3 class="font-semibold text-gray-700">{component.name}</h3>
                            <span class="text-gray-600">
                                {expandedComponents.has(component.name) ? '▼' : '▶'}
                            </span>
                        </div>
                        {#if expandedComponents.has(component.name)}
                            <pre class="p-4 bg-white whitespace-pre-wrap">
                                <code>{component.content}</code>
                            </pre>
                        {/if}
                    </div>
                {/each}
            </div>
        </div>
    {/if}

    {#if files.length === 0 && !error}
        <div class="text-gray-500">No files found in the directory</div>
    {/if}
</div>
