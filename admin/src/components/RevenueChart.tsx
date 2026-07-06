'use client';

import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { formatINR, formatINRCompact } from '@/lib/format';

/** A single point in the `/admin/analytics/revenue` time series. */
export interface RevenuePoint {
  /** Bucket label, e.g. "2026-06" or "Jun". */
  label: string;
  revenue: number;
  /** Optional: platform commission slice. */
  commission?: number;
}

export interface RevenueChartProps {
  data: RevenuePoint[];
  height?: number;
}

function ChartTooltip({
  active,
  payload,
  label,
}: {
  active?: boolean;
  payload?: Array<{ value: number; name: string; color: string }>;
  label?: string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border-2 border-ink bg-white px-3 py-2 shadow-brutal">
      <p className="mb-1 text-xs font-bold uppercase text-slate-500">{label}</p>
      {payload.map((p) => (
        <p key={p.name} className="flex items-center gap-2 text-sm font-bold text-ink">
          <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />
          {formatINR(p.value)}
        </p>
      ))}
    </div>
  );
}

export function RevenueChart({ data, height = 300 }: RevenueChartProps) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="revenueFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#fb2c63" stopOpacity={0.3} />
            <stop offset="100%" stopColor="#fb2c63" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="#eef2f7" vertical={false} />
        <XAxis
          dataKey="label"
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 12, fill: '#94a3b8' }}
          dy={8}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 12, fill: '#94a3b8' }}
          tickFormatter={(v) => formatINRCompact(v)}
          width={56}
        />
        <Tooltip content={<ChartTooltip />} cursor={{ stroke: '#ff97b5', strokeWidth: 1 }} />
        <Area
          type="monotone"
          dataKey="revenue"
          name="Revenue"
          stroke="#e60a4d"
          strokeWidth={2.5}
          fill="url(#revenueFill)"
          activeDot={{ r: 5, strokeWidth: 0 }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
