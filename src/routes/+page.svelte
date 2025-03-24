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

    function jumpToCycle(cycleNum: number) {
        const foundIndex = cycles.findIndex(c => c.cycle === cycleNum);
        if (foundIndex !== -1) {
            currentCycleIndex = foundIndex;
        }
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
                <div 
                    class="border rounded p-2 cursor-pointer hover:bg-gray-200 bg-white shadow-sm"
                    on:click={() => viewFile(file)}
                >
                    <h2 class="text-base font-semibold text-gray-700">{getDisplayFileName(file.name)}</h2>
                </div>
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

            <div class="columns-[200px] gap-2">
                {#each cycles[currentCycleIndex]?.components || [] as component}
                    <div 
                        class="break-inside-avoid mb-2 inline-block w-full"
                    >
                        <div 
                            class="{expandedComponents.has(component.name) 
                                ? component.name.toLowerCase().includes('free list')
                                    ? 'w-[280px]'
                                    : 'w-fit max-w-[800px]' 
                                : 'w-full'} 
                            border rounded overflow-hidden transition-all duration-200 bg-white shadow-sm"
                        >
                            <div 
                                class="bg-gray-100 p-1 cursor-pointer hover:bg-gray-200 flex justify-between items-center"
                                on:click={() => toggleComponent(component.name)}
                            >
                                <h3 class="font-semibold text-gray-700 text-xs px-1">{component.name}</h3>
                                <span class="text-gray-600 text-xs px-1">
                                    {expandedComponents.has(component.name) ? '▼' : '▶'}
                                </span>
                            </div>
                            {#if expandedComponents.has(component.name)}
                                <pre class="p-1 bg-white whitespace-pre-wrap text-xs overflow-x-auto">
                                    <code>{component.content}</code>
                                </pre>
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
