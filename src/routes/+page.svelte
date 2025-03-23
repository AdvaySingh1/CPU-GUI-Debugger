<script lang="ts">
    import { onMount } from 'svelte';

    type FileData = {
        name: string;
        content: string;
    };

    let files: FileData[] = [];
    let error: string | null = null;

    onMount(async () => {
        try {
            const response = await fetch('/api/files');
            if (!response.ok) throw new Error('Failed to fetch files');
            files = await response.json();
        } catch (e) {
            error = String(e);
        }
    });

    function openInNewTab(file: FileData) {
        const blob = new Blob([file.content], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        window.open(url, '_blank');
    }
</script>

<div class="p-4">
    <h1 class="text-2xl font-bold mb-4">Svelte Files from ~/470/gui_debugger</h1>
    
    {#if error}
        <div class="text-red-500">Error: {error}</div>
    {/if}

    <div class="grid grid-cols-3 gap-4">
        {#each files as file}
            <div 
                class="border rounded-lg p-4 cursor-pointer hover:bg-gray-100"
                on:click={() => openInNewTab(file)}
            >
                <h2 class="text-xl font-semibold">{file.name}</h2>
            </div>
        {/each}
    </div>

    {#if files.length === 0 && !error}
        <div class="text-gray-500">No Svelte files found in the directory</div>
    {/if}
</div>
