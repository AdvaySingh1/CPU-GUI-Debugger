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

    type RetireEnableInfo = {
        lastActiveCycle: number;
        pattern: string;
    };

    const PCSearchTarget = {
        Dispatch: 'Dispatch',
        IssueALU: 'Issue-ALU',
        IssueMULT: 'Issue-MULT',
        IssueLOAD: 'Issue-LOAD',
        Retire: 'Retire'
    } as const;

    type PCSearchTargetType = typeof PCSearchTarget[keyof typeof PCSearchTarget];

    let files: FileData[] = [];
    let error: string | null = null;
    let selectedFile: FileData | null = null;
    let cycles: CycleData[] = [];
    let currentCycleIndex = 0;
    let expandedComponents = new Set<string>();
    let componentPositions = new Map<string, Position>();
    let searchCycle = '';
    let searchPC = '';
    let searchPCTarget: PCSearchTargetType = PCSearchTarget.Dispatch;
    let searchError: string | null = null;
    let isDragging = false;
    let retireSignals: RetireSignalInfo[] = [];
    let lastDispatchActive: DispatchInfo | null = null;
    let lastRetireActive: RetireEnableInfo | null = null;
    let foundPCEntry: string | null = null;
    let foundPCComponent: string | null = null;
    let searchComponentTerm = '';
    let searchComponentResults: string[] = [];
    let focusedComponent: string | null = null;

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
        foundPCComponent = null;
        analyzeRetireSignals();
    }

    function analyzeRetireSignals() {
        retireSignals = [];
        lastDispatchActive = null;
        lastRetireActive = null;
        const robEntryMap = new Map<number, number>(); // Map of entry index to last active cycle

        // Process each cycle
        for (const cycle of cycles) {
            // Find the ROB component (previously named 'ROB Signals')
            const robComponent = cycle.components.find(comp => comp.name.includes('ROB'));
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

            // For the Retire enable signals, we actually need to look at the ROB Signals component
            // We already processed the ROB Signals component above for individual entries
            // Now we'll check if any of the entries were enabled in this cycle
            if (robComponent) {
                const lines = robComponent.content.split('\n');
                let anyEnabled = false;
                let pattern = '';

                // Check if any En[x] signals are high in this cycle
                for (const line of lines) {
                    const match = line.match(/En\[(\d+)\]:\s*(\d+)/);
                    if (match) {
                        const isEnabled = match[2] === '1';
                        if (isEnabled) {
                            anyEnabled = true;
                        }
                        // Build the pattern string (e.g., "101" for En[0]=1, En[1]=0, En[2]=1)
                        pattern += match[2];
                    }
                }

                // If any entries were enabled, update the last active cycle
                if (anyEnabled && pattern) {
                    lastRetireActive = {
                        lastActiveCycle: cycle.cycle,
                        pattern: pattern
                    };
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
            focusedComponent = null;
        } else {
            expandedComponents.add(componentName);
            focusedComponent = componentName;

            // If the component doesn't have a position yet, center it
            if (!componentPositions.has(componentName)) {
                const container = document.querySelector('.flex-1.relative.min-h-\[500px\]') as HTMLElement;
                if (container) {
                    const centerX = container.offsetWidth / 2 - 150; // Approximate half width of component
                    const centerY = container.offsetHeight / 2 - 100; // Approximate half height of component
                    componentPositions.set(componentName, { x: centerX, y: centerY });
                }
            }
        }
        expandedComponents = expandedComponents; // trigger reactivity
    }

    function searchComponents() {
        if (!searchComponentTerm.trim()) {
            searchComponentResults = [];
            return;
        }

        const currentComponents = cycles[currentCycleIndex]?.components || [];
        const term = searchComponentTerm.toLowerCase();

        // Find components that start with the search term
        searchComponentResults = currentComponents
            .filter(comp => comp.name.toLowerCase().startsWith(term))
            .map(comp => comp.name)
            .slice(0, 3); // Limit to 3 results
    }

    function selectSearchedComponent(componentName: string) {
        focusedComponent = componentName;
        expandedComponents.add(componentName);
        expandedComponents = expandedComponents; // trigger reactivity
        searchComponentTerm = '';
        searchComponentResults = [];

        // If the component doesn't have a position yet, center it
        if (!componentPositions.has(componentName)) {
            const container = document.querySelector('.flex-1.relative.min-h-\[500px\]') as HTMLElement;
            if (container) {
                const centerX = container.offsetWidth / 2 - 150; // Approximate half width of component
                const centerY = container.offsetHeight / 2 - 100; // Approximate half height of component
                componentPositions.set(componentName, { x: centerX, y: centerY });
            }
        }
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
        foundPCComponent = null;

        // Normalize the PC value (remove leading zeros and convert to lowercase for case-insensitive comparison)
        const normalizedPC = searchPC.replace(/^0+/, '').toLowerCase();

        // Search for PC in the selected component

        // Search through all cycles
        for (let i = 0; i < cycles.length; i++) {
            const cycle = cycles[i];

            // Search based on the selected target
            let result = false;
            switch (searchPCTarget) {
                case PCSearchTarget.Dispatch:
                    result = searchDispatchPC(cycle, normalizedPC, i);
                    break;

                case PCSearchTarget.IssueALU:
                    result = searchIssueALUPC(cycle, normalizedPC, i);
                    break;

                case PCSearchTarget.IssueMULT:
                    result = searchIssueMULTPC(cycle, normalizedPC, i);
                    break;

                case PCSearchTarget.IssueLOAD:
                    result = searchIssueLOADPC(cycle, normalizedPC, i);
                    break;

                case PCSearchTarget.Retire:
                    result = searchRetirePC(cycle, normalizedPC, i);
                    break;
            }

            if (result) {
                return;
            }
        }

        // If we get here, no match was found
        searchError = `PC ${searchPC} not found in any ${searchPCTarget} entry`;
    }

    function searchDispatchPC(cycle: CycleData, normalizedPC: string, cycleIndex: number): boolean {
        // Find the Dispatch component
        const dispatchComponent = cycle.components.find(comp => comp.name.includes('Dispatch'));
        if (!dispatchComponent) return false;

        // Parse the content to find PC values
        const content = dispatchComponent.content;
        const rsEntryMatches = [...content.matchAll(/RS_ENTRY\s*\[(\d+)\][\s\S]*?PC:\s*([0-9a-fA-F]+)/g)];

        // Check each PC value
        for (const match of rsEntryMatches) {
            const entryIndex = match[1];
            // Get the PC value and normalize it (remove leading zeros and convert to lowercase)
            const pcValue = match[2].toLowerCase().replace(/^0+/, '');

            // If we found a match
            if (pcValue === normalizedPC) {
                searchError = null;
                currentCycleIndex = cycleIndex;
                foundPCEntry = `RS_ENTRY[${entryIndex}]`;
                foundPCComponent = 'Dispatch';
                // Ensure the component is expanded
                expandedComponents.add('Dispatch');
                return true;
            }
        }

        return false;
    }

    function searchIssueALUPC(cycle: CycleData, normalizedPC: string, cycleIndex: number): boolean {
        // Find the Issue component
        const issueComponent = cycle.components.find(comp => comp.name.includes('Issue'));
        if (!issueComponent) return false;

        // Parse the content to find ALU packet PC values
        const content = issueComponent.content;
        const aluMatches = [...content.matchAll(/ISSUE_EXECUTE_ALU_PACKET ALU\s*\[(\d+)\][\s\S]*?PC:\s*([0-9a-fA-F]+)/g)];

        // Check each PC value
        for (const match of aluMatches) {
            const entryIndex = match[1];
            // Get the PC value and normalize it (remove leading zeros and convert to lowercase)
            const pcValue = match[2].toLowerCase().replace(/^0+/, '');

            // If we found a match
            if (pcValue === normalizedPC) {
                searchError = null;
                currentCycleIndex = cycleIndex;
                foundPCEntry = `ALU[${entryIndex}]`;
                foundPCComponent = 'Issue';
                // Ensure the component is expanded
                expandedComponents.add('Issue');
                return true;
            }
        }

        return false;
    }

    function searchIssueMULTPC(cycle: CycleData, normalizedPC: string, cycleIndex: number): boolean {
        // Find the Issue component
        const issueComponent = cycle.components.find(comp => comp.name.includes('Issue'));
        if (!issueComponent) return false;

        // Parse the content to find MULT packet NPC values
        const content = issueComponent.content;
        const multMatches = [...content.matchAll(/ISSUE_EXECUTE_MULT_PACKET MULT\s*\[(\d+)\][\s\S]*?NPC:\s*([0-9a-fA-F]+)/g)];

        // Check each NPC value (subtract 4 to get PC)
        for (const match of multMatches) {
            const entryIndex = match[1];
            // Get the NPC value, convert to number, subtract 4, convert back to hex string without leading zeros
            const npcValue = match[2];
            const npcDecimal = parseInt(npcValue, 16);
            const pcDecimal = npcDecimal - 4;
            const pcValue = pcDecimal.toString(16).toLowerCase().replace(/^0+/, '');

            // If we found a match
            if (pcValue === normalizedPC.toLowerCase()) {
                searchError = null;
                currentCycleIndex = cycleIndex;
                foundPCEntry = `MULT[${entryIndex}]`;
                foundPCComponent = 'Issue';
                // Ensure the component is expanded
                expandedComponents.add('Issue');
                return true;
            }
        }

        return false;
    }

    function searchIssueLOADPC(cycle: CycleData, normalizedPC: string, cycleIndex: number): boolean {
        // Find the Issue component
        const issueComponent = cycle.components.find(comp => comp.name.includes('Issue'));
        if (!issueComponent) return false;

        // Parse the content to find LOAD packet NPC values
        const content = issueComponent.content;
        const loadMatches = [...content.matchAll(/ISSUE_EXECUTE_LOAD_PACKET LOAD\s*\[(\d+)\][\s\S]*?NPC:\s*([0-9a-fA-F]+)/g)];

        // Check each NPC value (subtract 4 to get PC)
        for (const match of loadMatches) {
            const entryIndex = match[1];
            // Get the NPC value, convert to number, subtract 4, convert back to hex string without leading zeros
            const npcValue = match[2];
            const npcDecimal = parseInt(npcValue, 16);
            const pcDecimal = npcDecimal - 4;
            const pcValue = pcDecimal.toString(16).toLowerCase().replace(/^0+/, '');

            // If we found a match
            if (pcValue === normalizedPC.toLowerCase()) {
                searchError = null;
                currentCycleIndex = cycleIndex;
                foundPCEntry = `LOAD[${entryIndex}]`;
                foundPCComponent = 'Issue';
                // Ensure the component is expanded
                expandedComponents.add('Issue');
                return true;
            }
        }

        return false;
    }

    function searchRetirePC(cycle: CycleData, normalizedPC: string, cycleIndex: number): boolean {
        // Find the Retire component
        const retireComponent = cycle.components.find(comp => comp.name.includes('Retire'));
        if (!retireComponent) return false;

        // Parse the content to find COMMIT_PACKET Debug Output entries
        const content = retireComponent.content;

        // Search for PC in Retire component

        // Simple approach: directly look for NPC values and check if they match PC-4
        const lines = content.split('\n');
        let inCommitPacket = false;
        let currentIndex = '';
        let currentNPC = '';
        let currentValid = '';

        for (const line of lines) {
            const trimmedLine = line.trim();

            // Check if we're entering a COMMIT_PACKET section
            if (trimmedLine.includes('COMMIT_PACKET Debug Output for index')) {
                inCommitPacket = true;
                const indexMatch = trimmedLine.match(/\[(\d+)\]/);
                if (indexMatch) {
                    currentIndex = indexMatch[1];
                }
                continue;
            }

            // If we're in a COMMIT_PACKET section, look for NPC and Valid
            if (inCommitPacket) {
                // Check for NPC
                if (trimmedLine.startsWith('NPC:')) {
                    const npcMatch = trimmedLine.match(/NPC:\s*([0-9a-fA-F]+)/);
                    if (npcMatch) {
                        currentNPC = npcMatch[1];
                        // Found NPC value

                        // Check for a match immediately after finding NPC
                        const npcDecimal = parseInt(currentNPC, 16);
                        const pcDecimal = npcDecimal - 4;
                        const pcValue = pcDecimal.toString(16).toLowerCase().replace(/^0+/, '');

                        // Calculated PC from NPC

                        // If we found a match
                        if (pcValue === normalizedPC.toLowerCase()) {
                            // Match found
                            searchError = null;
                            currentCycleIndex = cycleIndex;
                            foundPCEntry = `COMMIT[${currentIndex}]`;
                            foundPCComponent = 'Retire';
                            // Ensure the component is expanded
                            expandedComponents.add('Retire');
                            return true;
                        }
                    }
                }

                // Check for Valid
                if (trimmedLine.startsWith('Valid:')) {
                    const validMatch = trimmedLine.match(/Valid:\s*(\d+)/);
                    if (validMatch) {
                        currentValid = validMatch[1];
                        // Found Valid flag

                        // If we've found NPC, check for a match regardless of Valid flag
                        if (currentNPC) {
                            // Calculate PC from NPC (subtract 4)
                            const npcDecimal = parseInt(currentNPC, 16);
                            const pcDecimal = npcDecimal - 4;
                            const pcValue = pcDecimal.toString(16).toLowerCase().replace(/^0+/, '');

                            // If we found a match
                            if (pcValue === normalizedPC.toLowerCase()) {
                                searchError = null;
                                currentCycleIndex = cycleIndex;
                                foundPCEntry = `COMMIT[${currentIndex}]`;
                                foundPCComponent = 'Retire';
                                // Ensure the component is expanded
                                expandedComponents.add('Retire');
                                return true;
                            }
                        }
                    }
                }

                // Check if we're exiting the COMMIT_PACKET section
                if (trimmedLine.startsWith('Arch Tags') ||
                    trimmedLine.startsWith('store2Dcache') ||
                    trimmedLine.startsWith('MEM_COMMAND')) {
                    inCommitPacket = false;
                    currentIndex = '';
                    currentNPC = '';
                    currentValid = '';
                }
            }
        }

        // If we get here, we didn't find a match
        return false;
    }

    function startDrag(event: MouseEvent, componentName: string) {
        // Don't start drag if we're not clicking on the drag handle
        if (!(event.target as HTMLElement).closest('.drag-handle')) {
            return;
        }
        // Prevent default to avoid text selection during drag
        event.preventDefault();

        // Stop event propagation to prevent conflicts with other handlers
        event.stopPropagation();

        // Prevent the click event from firing after drag
        const handleClick = (e: Event) => {
            e.stopPropagation();
            document.removeEventListener('click', handleClick, true);
        };
        document.addEventListener('click', handleClick, true);

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

<style>
    :global(body) {
        background-color: #111827; /* bg-gray-900 */
        margin: 0;
        padding: 0;
        min-height: 100vh;
        width: 100%;
    }
</style>

<div class="p-2 bg-gray-900 text-gray-100 min-h-screen w-full h-full fixed inset-0 overflow-auto">
    <h1 class="text-2xl font-bold mb-2 text-gray-100">470 GUI Debugger</h1>

    {#if error}
        <div class="text-red-500 text-sm">Error: {error}</div>
    {/if}

    {#if !selectedFile}
        <div class="grid grid-cols-4 gap-2">
            {#each files as file}
                <button
                    type="button"
                    class="border border-gray-700 rounded p-2 cursor-pointer hover:bg-gray-700 bg-gray-800 shadow-sm text-left text-gray-100"
                    on:click={() => viewFile(file)}
                    on:keydown={(e) => e.key === 'Enter' && viewFile(file)}
                >
                    <h2 class="text-base font-semibold text-gray-100">{getDisplayFileName(file.name)}</h2>
                </button>
            {/each}
        </div>
    {:else}
        <div class="mb-2 flex items-center gap-2">
            <button
                class="bg-blue-700 text-white px-2 py-1 rounded text-sm hover:bg-blue-600"
                on:click={() => selectedFile = null}
            >
                Back to Files
            </button>
            <h2 class="text-lg font-semibold text-gray-100">{getDisplayFileName(selectedFile.name)}</h2>
        </div>

        <div class="border border-gray-700 rounded p-2 bg-gray-800 shadow-md text-gray-100">
            <div class="flex items-center justify-between mb-2">
                <div class="flex gap-2 items-center">
                    <div class="flex items-center gap-2">
                        <div class="flex items-center gap-1">
                            <input
                                type="number"
                                bind:value={searchCycle}
                                placeholder="Search cycle..."
                                class="px-1 py-0.5 border border-gray-600 rounded w-24 text-sm bg-gray-700 text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-400"
                                on:keydown={(e) => e.key === 'Enter' && searchByCycle()}
                            />
                            <button
                                class="bg-blue-700 text-white px-2 py-0.5 rounded text-sm hover:bg-blue-600"
                                on:click={searchByCycle}
                            >
                                Go
                            </button>
                        </div>

                        <div class="flex items-center gap-1">
                            <div class="flex flex-col gap-1">
                                <div class="flex items-center gap-1">
                                    <input
                                        type="text"
                                        bind:value={searchPC}
                                        placeholder="Search PC..."
                                        class="px-1 py-0.5 border border-gray-600 rounded w-24 text-sm bg-gray-700 text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-400"
                                        on:keydown={(e) => e.key === 'Enter' && searchByPC()}
                                        on:input={() => { if (!searchPC) { foundPCEntry = null; foundPCComponent = null; } }}
                                    />
                                    <button
                                        class="bg-green-700 text-white px-2 py-0.5 rounded text-sm hover:bg-green-600"
                                        on:click={searchByPC}
                                    >
                                        Find PC
                                    </button>
                                </div>
                                <select
                                    bind:value={searchPCTarget}
                                    class="px-1 py-0.5 border border-gray-600 rounded text-xs bg-gray-700 text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-400"
                                >
                                    <option value={PCSearchTarget.Dispatch}>Dispatch</option>
                                    <option value={PCSearchTarget.IssueALU}>Issue-ALU</option>
                                    <option value={PCSearchTarget.IssueMULT}>Issue-MULT</option>
                                    <option value={PCSearchTarget.IssueLOAD}>Issue-LOAD</option>
                                    <option value={PCSearchTarget.Retire}>Retire</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    <button
                        class="bg-gray-700 text-gray-100 px-2 py-0.5 rounded text-sm {currentCycleIndex === 0 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-600'}"
                        on:click={prevCycle}
                        disabled={currentCycleIndex === 0}
                    >
                        &lt;
                    </button>
                    <span class="text-gray-100 text-sm">Cycle {cycles[currentCycleIndex]?.cycle}</span>
                    <button
                        class="bg-gray-700 text-gray-100 px-2 py-0.5 rounded text-sm {currentCycleIndex === cycles.length - 1 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-gray-600'}"
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

            <div class="flex h-full">
                <!-- Left sidebar for collapsed components -->
                <div class="w-[200px] flex flex-col gap-1 pr-2 border-r border-gray-700 mr-2 bg-gray-900">
                    <div class="mb-2">
                        <input
                            type="text"
                            bind:value={searchComponentTerm}
                            placeholder="Search components..."
                            class="px-1 py-0.5 border border-gray-600 rounded w-full text-sm bg-gray-700 text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-400"
                            on:input={searchComponents}
                            on:keydown={(e) => e.key === 'Enter' && searchComponentResults.length > 0 && selectSearchedComponent(searchComponentResults[0])}
                        />
                        {#if searchComponentResults.length > 0}
                            <div class="absolute z-20 mt-1 w-[180px] bg-gray-800 border border-gray-700 rounded shadow-lg">
                                {#each searchComponentResults as result}
                                    <button
                                        class="w-full text-left px-2 py-1 text-sm text-gray-100 hover:bg-gray-700"
                                        on:click={() => selectSearchedComponent(result)}
                                    >
                                        {result}
                                    </button>
                                {/each}
                            </div>
                        {/if}
                    </div>

                    {#each cycles[currentCycleIndex]?.components || [] as component}
                        <!-- Only show in sidebar if not expanded or focused -->
                        {#if !expandedComponents.has(component.name) || component.name !== focusedComponent}
                            <button
                                class="text-left px-2 py-1 text-xs text-gray-100 bg-gray-800 hover:bg-gray-700 rounded truncate"
                                on:click={() => selectSearchedComponent(component.name)}
                            >
                                {component.name}
                            </button>
                        {/if}
                    {/each}
                </div>

                <!-- Main content area for expanded components -->
                <div class="flex-1 relative min-h-[500px] bg-gray-900">
                    {#each cycles[currentCycleIndex]?.components || [] as component}
                        <!-- Only show in main area if expanded or focused -->
                        {#if expandedComponents.has(component.name)}
                            <div
                                class="mb-2 inline-block component-container {component.name === focusedComponent ? 'z-10' : 'z-1'}"
                                style="{componentPositions.has(component.name) ? `position: absolute; left: ${componentPositions.get(component.name)?.x}px; top: ${componentPositions.get(component.name)?.y}px;` : ''}"
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
                                    border border-gray-700 rounded overflow-hidden transition-all duration-200 bg-gray-800 shadow-md"
                                >
                                    <button
                                        type="button"
                                        class="component-header bg-gray-700 p-1 cursor-move hover:bg-gray-600 flex justify-between items-center w-full text-left text-gray-100"
                                        on:click={() => toggleComponent(component.name)}
                                        on:keydown={(e) => e.key === 'Enter' && toggleComponent(component.name)}
                                    >
                                        <div
                                            class="flex items-center gap-1 flex-1"
                                        >
                                            <div
                                                class="drag-handle p-1 cursor-move"
                                                role="button"
                                                tabindex="0"
                                                aria-label="Drag component"
                                                on:mousedown={(e) => startDrag(e, component.name)}
                                                on:keydown={(e) => e.key === 'Enter' && toggleComponent(component.name)}
                                            >
                                                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                                    <circle cx="9" cy="5" r="1"/>
                                                    <circle cx="9" cy="12" r="1"/>
                                                    <circle cx="9" cy="19" r="1"/>
                                                    <circle cx="15" cy="5" r="1"/>
                                                    <circle cx="15" cy="12" r="1"/>
                                                    <circle cx="15" cy="19" r="1"/>
                                                </svg>
                                            </div>
                                            <h3 class="font-semibold text-gray-100 text-xs">{component.name}</h3>
                                        </div>
                                        <span class="text-gray-300 text-xs px-1">
                                            {expandedComponents.has(component.name) ? '▼' : '▶'}
                                        </span>
                                    </button>
                                    {#if expandedComponents.has(component.name)}
                                        <pre class="p-1 bg-gray-900 text-gray-100 whitespace-pre-wrap text-xs overflow-x-auto">
                                            <code>{component.content}</code>
                                        </pre>

                                        {#if component.name.includes('ROB')}
                                            <div class="p-2 bg-blue-900 border-t border-blue-700">
                                                {#if lastRetireActive}
                                                    <h4 class="font-semibold text-xs text-blue-200 mb-1">Last Cycle With Any Active ROB Enable:</h4>
                                                    <div class="bg-blue-800 p-1 rounded text-xs text-blue-100">
                                                        Cycle {lastRetireActive.lastActiveCycle}: Pattern: {lastRetireActive.pattern}
                                                    </div>
                                                {/if}
                                            </div>
                                        {/if}

                                        {#if component.name.includes('Dispatch')}
                                            <div class="p-2 bg-green-900 border-t border-green-700">
                                                {#if lastDispatchActive}
                                                    <h4 class="font-semibold text-xs text-green-200 mb-1">Last Active Dispatch Signal:</h4>
                                                    <div class="bg-green-800 p-1 rounded text-xs mb-2 text-green-100">
                                                        Cycle {lastDispatchActive.lastActiveCycle}: En: {lastDispatchActive.pattern}
                                                    </div>
                                                {/if}

                                                {#if foundPCEntry && foundPCComponent === 'Dispatch'}
                                                    <h4 class="font-semibold text-xs text-green-200 mb-1">Found PC Match:</h4>
                                                    <div class="bg-yellow-700 p-1 rounded text-xs border border-yellow-500 text-yellow-100">
                                                        Entry: {foundPCEntry} - PC: {searchPC}
                                                    </div>
                                                {/if}
                                            </div>
                                        {/if}

                                        {#if component.name.includes('Issue') && foundPCComponent === 'Issue' && foundPCEntry}
                                            <div class="p-2 bg-blue-900 border-t border-blue-700">
                                                <h4 class="font-semibold text-xs text-blue-200 mb-1">Found PC Match:</h4>
                                                <div class="bg-yellow-700 p-1 rounded text-xs border border-yellow-500 text-yellow-100">
                                                    Entry: {foundPCEntry} - PC: {searchPC}
                                                </div>
                                            </div>
                                        {/if}

                                        {#if component.name.includes('Retire')}
                                            <div class="p-2 bg-purple-900 border-t border-purple-700">

                                                {#if foundPCComponent === 'Retire' && foundPCEntry}
                                                    <h4 class="font-semibold text-xs text-purple-200 mb-1">Found PC Match:</h4>
                                                    <div class="bg-yellow-700 p-1 rounded text-xs border border-yellow-500 text-yellow-100">
                                                        Entry: {foundPCEntry} - PC: {searchPC}
                                                    </div>
                                                {/if}
                                            </div>
                                        {/if}
                                    {/if}
                                </div>
                            </div>
                        {/if}
                    {/each}
                </div>
            </div>
        </div>
    {/if}

    {#if files.length === 0 && !error}
        <div class="text-gray-500 text-sm">No files found in the directory</div>
    {/if}
</div>
