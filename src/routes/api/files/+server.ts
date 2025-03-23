import { json } from '@sveltejs/kit';
import { readdir, readFile } from 'fs/promises';
import { join } from 'path';
import { homedir } from 'os';

export async function GET() {
    try {
        const baseDir = join(homedir(), '470', 'gui_debugger');
        const files = await readdir(baseDir);
        const svelteFiles = files.filter(file => file.endsWith('_svelte'));
        
        const fileContents = await Promise.all(
            svelteFiles.map(async (filename) => {
                const content = await readFile(join(baseDir, filename), 'utf-8');
                return {
                    name: filename,
                    content
                };
            })
        );

        return json(fileContents);
    } catch (error) {
        return new Response(String(error), { status: 500 });
    }
}