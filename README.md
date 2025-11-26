# OpenWebUI + LiteLLM Stack

A production-ready, self-hosted AI chat interface powered by OpenWebUI with LiteLLM as a unified model proxy. This stack provides access to multiple AI providers (OpenAI, Anthropic, Google, DeepSeek) through a single interface with usage tracking, caching, and automatic updates.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         NGINX                                │
│              (SSL Termination & Reverse Proxy)               │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
┌───────────────┐           ┌───────────────┐
│   OpenWebUI   │──────────▶│  LiteLLM      │
│  (Port 3000)  │           │  (Port 4000)  │
└───────────────┘           └───────┬───────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
              ┌─────────┐    ┌─────────┐    ┌─────────┐
              │ OpenAI  │    │Anthropic│    │ Google  │
              │ GPT-4/5 │    │ Claude  │    │ Gemini  │
              └─────────┘    └─────────┘    └─────────┘
```

## Features

- **Multi-Provider Access**: Route requests to OpenAI, Anthropic, Google Gemini, DeepSeek, and local Ollama models
- **Unified API**: Single OpenAI-compatible endpoint for all models
- **Usage Tracking**: Full spend and token tracking in PostgreSQL
- **Response Caching**: Redis-backed caching to reduce API costs
- **Streaming Optimized**: All layers configured for instant token streaming
- **Auto-Updates**: Watchtower automatically updates containers daily
- **Monitoring**: Prometheus metrics for observability

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| open-webui | ghcr.io/open-webui/open-webui:main | Chat interface |
| litellm-proxy | ghcr.io/berriai/litellm:main-stable | Model proxy |
| litellm-db | postgres:16 | Usage tracking database |
| litellm-redis | redis:8 | Response caching |
| litellm-prometheus | prom/prometheus:latest | Metrics collection |
| ollama | ollama/ollama:latest | Local model inference |
| watchtower | containrrr/watchtower:latest | Auto-updates |

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Domain with SSL (or use Cloudflare Tunnel)
- API keys for your chosen providers

### Installation

1. Clone this repository:
```bash
git clone https://github.com/AllDayAutomationsai/openwebui-litellm-stack.git
cd openwebui-litellm-stack
```

2. Copy and configure environment variables:
```bash
cp .env.example .env
# Edit .env with your API keys
```

3. Start the stack:
```bash
docker compose up -d
```

4. Access OpenWebUI at `http://localhost:3000`

## Configuration

### Environment Variables (.env)

```bash
# Required API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
DEEPSEEK_API_KEY=...

# LiteLLM
LITELLM_MASTER_KEY=your-master-key

# Database
POSTGRES_PASSWORD=your-db-password
```

### Adding Models

Edit `litellm-config.yaml` to add or modify models:

```yaml
model_list:
  - model_name: my-model
    litellm_params:
      model: provider/model-name
      api_key: os.environ/API_KEY_VAR
      timeout: 600
```

### Nginx Configuration

Sample Nginx config for reverse proxy with streaming:

```nginx
location / {
    proxy_pass http://localhost:3000;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_cache off;
    chunked_transfer_encoding on;
    tcp_nodelay on;
}
```

## Usage Tracking

LiteLLM automatically logs all requests to PostgreSQL. Query usage with:

```bash
docker exec litellm-db psql -U litellmadmin -d litellm_db \
  -c 'SELECT * FROM "Last30dModelsBySpend" ORDER BY total_spend DESC;'
```

## Maintenance

### Backups
```bash
# Backup volumes
docker compose stop
tar -czf backup.tar.gz /var/lib/docker/volumes/litellm-db /var/lib/docker/volumes/open-webui
docker compose start
```

### Updates
Watchtower handles automatic updates. Manual update:
```bash
docker compose pull
docker compose up -d
```

### Logs
```bash
docker logs litellm-proxy -f
docker logs open-webui -f
```

## File Structure

```
.
├── docker-compose.yml      # Main stack definition
├── litellm-config.yaml     # Model configuration
├── .env.example            # Environment template
├── .env                    # Your secrets (gitignored)
├── monitor.sh              # Health check script
├── backup.sh               # Backup script
└── README.md               # This file
```

## Contributing

1. Fork this repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Security Notes

- Never commit `.env` files or API keys
- Use strong passwords for the database
- Keep containers updated
- Use HTTPS in production

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- [OpenWebUI](https://github.com/open-webui/open-webui)
- [LiteLLM](https://github.com/BerriAI/litellm)
- [Ollama](https://github.com/ollama/ollama)
