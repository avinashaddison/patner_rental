# Companion Ranchi — Admin Panel

Next.js 14 (App Router, TypeScript, Tailwind) admin console for the **Companion Ranchi**
companionship marketplace. Manage companions, KYC, users, bookings, payments, payouts,
complaints, support and settings.

> Safety guardrails baked into the product: **18+ only**, **public-place meetings only**,
> **companionship activities only** (coffee, movies, shopping, events, city tours, networking,
> conversation). Not an escort/adult service.

## Stack

- Next.js 14 App Router + React 18 + TypeScript
- Tailwind CSS (clean white surface, purple `#6D28D9` accent, rounded-2xl cards, soft shadows)
- SWR for data fetching, Recharts for charts, lucide-react icons, clsx

## Getting started

```bash
cd companion-ranchi/admin
cp .env.example .env.local       # set NEXT_PUBLIC_API_BASE_URL
npm install
npm run dev                      # http://localhost:3000
```

The panel talks to the backend at `${NEXT_PUBLIC_API_BASE_URL}/api/admin/*` (default
`http://localhost:4000`). Sign in at `/login` with admin credentials
(`POST /admin/auth/login`). The JWT is stored in a cookie + localStorage and attached as
`Authorization: Bearer <token>` on every request.

## Scripts

| Script          | Description                  |
| --------------- | ---------------------------- |
| `npm run dev`   | Dev server on port 3000      |
| `npm run build` | Production build             |
| `npm run start` | Serve the production build   |
| `npm run lint`  | ESLint (next/core-web-vitals)|

## Project layout

```
src/
  app/
    layout.tsx                 root layout (Inter font, globals)
    globals.css                tailwind + base styles
    page.tsx                   redirect → /dashboard or /login
    login/page.tsx             admin sign-in
    (dashboard)/
      layout.tsx               sidebar + topbar shell + auth guard
      dashboard/page.tsx       KPI cards + revenue chart
  components/
    Sidebar.tsx                nav (Dashboard, Companions, KYC, … Settings)
    Topbar.tsx                 admin name + logout
    RevenueChart.tsx           recharts area chart
    ui/                        Button, Card, StatCard, DataTable, Badge, Modal,
                               Input, Select, PageHeader, Spinner (+ barrel index.ts)
  lib/
    api.ts                     apiFetch<T>(path, opts) — admin base + JWT + envelope
    auth.ts                    login / logout / useAuthGuard
    format.ts                  INR money + date helpers
    cn.ts                      className combiner
```

## Adding a feature page (for other agents)

Admin pages are filesystem-routed. To add e.g. the Bookings page:

1. Create `src/app/(dashboard)/bookings/page.tsx` (a `'use client'` component).
2. Import shared modules — **do not redefine them**:

   ```tsx
   import { PageHeader, DataTable, StatusBadge, Button } from '@/components/ui';
   import { apiFetch, apiFetchList } from '@/lib/api';
   import { formatINR, formatDateTime } from '@/lib/format';
   ```

3. The Sidebar already links to `/bookings`, so the page lights up automatically — no shared
   file needs editing.

### Data fetching pattern

```tsx
import useSWR from 'swr';
import { swrFetcher } from '@/lib/api';

const { data, isLoading } = useSWR('/bookings?status=PENDING&page=1', swrFetcher);
```

For list endpoints that need pagination `meta`, use `apiFetchList<T>(path)` which returns
`{ data, meta }`. The `DataTable` `pagination` prop consumes `{ page, limit, total, onPageChange }`.

## API contract

See [`../docs/API.md`](../docs/API.md) for the full admin route table and
[`../docs/DATA_MODEL.md`](../docs/DATA_MODEL.md) for entity/enum definitions. Status enum →
badge tone mapping lives in `components/ui/Badge.tsx` (`StatusBadge`).

## Docker

```bash
docker build -t companion-ranchi-admin \
  --build-arg NEXT_PUBLIC_API_BASE_URL=https://api.companionranchi.com .
docker run -p 3000:3000 companion-ranchi-admin
```
