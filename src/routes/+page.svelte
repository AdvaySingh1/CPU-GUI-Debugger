<script lang="ts">
    import { onMount } from 'svelte';

    type FileData = {
        name: string;
        content: string;
    };

    type CycleData = {
        cycle: number;
        content: string;
    };

    let files: FileData[] = [];
    let error: string | null = null;
    let selectedFile: FileData | null = null;
    let cycles: CycleData[] = [];
    let currentCycleIndex = 0;

    onMount(async () => {
        try {
            const response = await fetch('/api/files');
            if (!response.ok) throw new Error('Failed to fetch files');
            files = await response.json();
        } catch (e) {
            error = String(e);
        }
    });

    function parseCycles(content: string): CycleData[] {
        const cycleRegex = /\$\$\$ (\d+)\n([\s\S]*?)(?=\$\$\$ \d+|$)/g;
        const cycles: CycleData[] = [];
        let match;

        while ((match = cycleRegex.exec(content)) !== null) {
            cycles.push({
                cycle: parseInt(match[1]),
                content: match[2].trim()
            });
        }

        return cycles;
    }

    function viewFile(file: FileData) {
        selectedFile = file;
        cycles = parseCycles(file.content);
        currentCycleIndex = 0;
    }

    function nextCycle() {
        if (currentCycleIndex < cycles.length - 1) {
            currentCycleIndex++;
        }
    }

    function prevCycle() {
        if (currentCycleIndex > 0) {
            currentCycleIndex--;
        }
    }
</script>

<div class="p-4">
    <h1 class="text-2xl font-bold mb-4">Svelte Files from ~/470/gui_debugger</h1>
    
    {#if error}
        <div class="text-red-500">Error: {error}</div>
    {/if}

    {#if !selectedFile}
        <div class="grid grid-cols-3 gap-4">
            {#each files as file}
                <div 
                    class="border rounded-lg p-4 cursor-pointer hover:bg-gray-100"
                    on:click={() => viewFile(file)}
                >
                    <h2 class="text-xl font-semibold">{file.name}</h2>
                </div>
            {/each}
        </div>
    {:else}
        <div class="mb-4">
            <button 
                class="bg-blue-500 text-white px-4 py-2 rounded"
                on:click={() => selectedFile = null}
            >
                Back to Files
            </button>
        </div>

        <div class="border rounded-lg p-4">
            <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold">{selectedFile.name}</h2>
                <div class="flex gap-4 items-center">
                    <button 
                        class="bg-gray-200 px-4 py-2 rounded {currentCycleIndex === 0 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-300'}"
                        on:click={prevCycle}
                        disabled={currentCycleIndex === 0}
                    >
                        &lt;
                    </button>
                    <span>Cycle {cycles[currentCycleIndex]?.cycle}</span>
                    <button 
                        class="bg-gray-200 px-4 py-2 rounded {currentCycleIndex === cycles.length - 1 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-300'}"
                        on:click={nextCycle}
                        disabled={currentCycleIndex === cycles.length - 1}
                    >
                        &gt;
                    </button>
                </div>
            </div>
            <pre class="bg-gray-100 p-4 rounded overflow-x-auto whitespace-pre-wrap">
                <code>{cycles[currentCycleIndex]?.content || 'No content available'}</code>
            </pre>
        </div>
    {/if}

    {#if files.length === 0 && !error}
        <div class="text-gray-500">No Svelte files found in the directory</div>
    {/if}
</div>
