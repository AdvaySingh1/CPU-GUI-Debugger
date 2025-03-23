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
</script>

<div class="p-4">
    <h1 class="text-2xl font-bold mb-4">Svelte Files from ~/470/gui_debugger</h1>
    
    {#if error}
        <div class="text-red-500">Error: {error}</div>
    {/if}

    {#each files as file}
        <div class="mb-8 border rounded-lg p-4">
            <h2 class="text-xl font-semibold mb-2">{file.name}</h2>
            <pre class="bg-gray-100 p-4 rounded overflow-x-auto">
                <code>{file.content}</code>
            </pre>
        </div>
    {/each}

    {#if files.length === 0 && !error}
        <div class="text-gray-500">No Svelte files found in the directory</div>
    {/if}
</div>
