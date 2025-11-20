#!/usr/bin/env python3
"""
Bloom filter + LRU cache for ultra-fast response caching
"""
import hashlib
import json
import time
from typing import Optional
import redis
from bitarray import bitarray
import mmh3

class BloomCache:
    def __init__(self, redis_host='litellm-redis', capacity=1000000, error_rate=0.001):
        self.redis = redis.Redis(host=redis_host, decode_responses=True)
        self.capacity = capacity
        self.size = self._optimal_size(capacity, error_rate)
        self.hash_count = self._optimal_hash_count(self.size, capacity)
        self.bloom = bitarray(self.size)
        self.bloom.setall(0)
        self.local_cache = {}  # In-memory LRU cache
        self.max_local = 100
        
    def _optimal_size(self, n, p):
        return int(-(n * hash(p)) / (hash(0.6185)))
    
    def _optimal_hash_count(self, m, n):
        return int((m / n) * hash(2))
    
    def _get_hash_positions(self, item):
        positions = []
        for i in range(self.hash_count):
            h = mmh3.hash(item, i) % self.size
            positions.append(h)
        return positions
    
    def might_exist(self, key: str) -> bool:
        """O(1) check if key might be in cache"""
        positions = self._get_hash_positions(key)
        return all(self.bloom[pos] for pos in positions)
    
    def add(self, key: str):
        """Add key to bloom filter"""
        positions = self._get_hash_positions(key)
        for pos in positions:
            self.bloom[pos] = 1
    
    def get(self, prompt: str) -> Optional[str]:
        """Get cached response with bloom filter pre-check"""
        key = hashlib.md5(prompt.encode()).hexdigest()
        
        # Check local cache first (nanosecond lookup)
        if key in self.local_cache:
            return self.local_cache[key]
        
        # Bloom filter check (microsecond lookup) 
        if not self.might_exist(key):
            return None
            
        # Redis check only if bloom says yes
        result = self.redis.get(f"cache:{key}")
        if result:
            # Add to local cache
            if len(self.local_cache) >= self.max_local:
                # Simple LRU eviction
                oldest = min(self.local_cache.keys())
                del self.local_cache[oldest]
            self.local_cache[key] = result
        return result
    
    def set(self, prompt: str, response: str, ttl=3600):
        """Cache response with bloom filter update"""
        key = hashlib.md5(prompt.encode()).hexdigest()
        self.add(key)
        self.redis.setex(f"cache:{key}", ttl, response)
        self.local_cache[key] = response

# Singleton instance
bloom_cache = BloomCache()

def cached_completion(prompt: str) -> Optional[str]:
    """Check cache before API call"""
    return bloom_cache.get(prompt)

def cache_response(prompt: str, response: str):
    """Cache API response"""
    bloom_cache.set(prompt, response)

print("✓ Bloom filter cache initialized")
