// Predictive prefetching for OpenWebUI
(function() {
    const prefetchCache = new Map();
    const prefetchQueue = [];
    let typingTimer;
    const DEBOUNCE_MS = 300;
    const MIN_LENGTH = 10;
    
    // Common prompt patterns that trigger prefetch
    const prefetchPatterns = [
        { pattern: /^(what|who|when|where|why|how)\s+/i, prefetch: true },
        { pattern: /^explain\s+/i, prefetch: true },
        { pattern: /^write\s+.*\s+(code|script|function)/i, prefetch: true },
        { pattern: /^translate\s+/i, prefetch: true },
        { pattern: /^summarize\s+/i, prefetch: true },
        { pattern: /weather\s+in\s+/i, prefetch: 'weather' },
        { pattern: /stock\s+price/i, prefetch: 'finance' },
        { pattern: /latest\s+news/i, prefetch: 'news' }
    ];
    
    // Intercept input events
    function interceptInput() {
        const inputs = document.querySelectorAll('textarea, input[type="text"]');
        inputs.forEach(input => {
            input.addEventListener('input', handleTyping);
            input.addEventListener('keydown', handleKeydown);
        });
    }
    
    function handleTyping(e) {
        clearTimeout(typingTimer);
        const text = e.target.value;
        
        if (text.length < MIN_LENGTH) return;
        
        typingTimer = setTimeout(() => {
            predictAndPrefetch(text);
        }, DEBOUNCE_MS);
    }
    
    function handleKeydown(e) {
        // If Enter is pressed and we have a prefetched result
        if (e.key === 'Enter' && !e.shiftKey) {
            const text = e.target.value;
            const cached = prefetchCache.get(text);
            if (cached) {
                console.log('🚀 Using prefetched response!');
                // Inject response immediately
                injectResponse(cached);
            }
        }
    }
    
    function predictAndPrefetch(text) {
        // Check patterns
        for (const rule of prefetchPatterns) {
            if (rule.pattern.test(text)) {
                // Start prefetch
                prefetchCompletion(text);
                break;
            }
        }
    }
    
    async function prefetchCompletion(prompt) {
        if (prefetchCache.has(prompt)) return;
        
        console.log('🔮 Prefetching:', prompt.substring(0, 30) + '...');
        
        // Create abort controller for cancellation
        const controller = new AbortController();
        prefetchQueue.push(controller);
        
        try {
            const response = await fetch('/api/chat/completions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Prefetch': 'true'
                },
                body: JSON.stringify({
                    model: 'gpt-4-turbo',
                    messages: [{ role: 'user', content: prompt }],
                    stream: true,
                    temperature: 0.7,
                    max_tokens: 150
                }),
                signal: controller.signal
            });
            
            if (response.ok) {
                const reader = response.body.getReader();
                let result = '';
                
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    result += new TextDecoder().decode(value);
                    
                    // Store partial results
                    prefetchCache.set(prompt, result);
                    
                    // Limit cache size
                    if (prefetchCache.size > 20) {
                        const firstKey = prefetchCache.keys().next().value;
                        prefetchCache.delete(firstKey);
                    }
                }
            }
        } catch (err) {
            if (err.name !== 'AbortError') {
                console.error('Prefetch error:', err);
            }
        }
    }
    
    function injectResponse(response) {
        // Find response area and inject
        const responseArea = document.querySelector('.response-area, .output, [data-response]');
        if (responseArea) {
            responseArea.textContent = response;
            responseArea.classList.add('prefetched');
        }
    }
    
    // Cancel old prefetches
    function cancelOldPrefetches() {
        while (prefetchQueue.length > 2) {
            const controller = prefetchQueue.shift();
            controller.abort();
        }
    }
    
    // Initialize on page load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', interceptInput);
    } else {
        interceptInput();
    }
    
    // Re-initialize on dynamic content
    const observer = new MutationObserver(interceptInput);
    observer.observe(document.body, { childList: true, subtree: true });
    
    console.log('✓ Predictive prefetching enabled');
})();
