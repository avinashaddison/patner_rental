'use client';

/**
 * Admin → Settings
 *
 * Runtime configuration for the marketplace. These key/value settings drive live
 * behaviour: the platform commission applied to every booking, the referral reward
 * credited to a referrer, the minimum a companion may withdraw, and the list of
 * cities the marketplace operates in.
 *
 * Each setting is saved independently so a single typo never blocks the whole form.
 *
 * Backed by (docs/API.md → ADMIN API):
 *   GET /admin/settings            (all settings)
 *   PUT /admin/settings/:key       { value }
 *
 * Seed keys (DATA_MODEL.md → settings):
 *   commission_rate (20) · referral_reward (100) · min_payout (500)
 *   booking_durations ([1,2,4,6]) · cities (["Ranchi"])
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import useSWR from 'swr';
import {
  CheckCircle2,
  Image as ImageIcon,
  ImagePlus,
  IndianRupee,
  MapPin,
  Percent,
  Plus,
  QrCode,
  Save,
  SlidersHorizontal,
  Trash2,
  Wallet,
  X,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card, CardHeader } from '@/components/ui/Card';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';
import { LoadingState } from '@/components/ui/Spinner';
import { apiFetch, swrFetcher, ApiError, ADMIN_API_BASE, getToken } from '@/lib/api';
import type { AdminSetting } from '@/lib/types';

const COMMISSION_KEY = 'commission_rate';
const REFERRAL_KEY = 'referral_reward';
const MIN_PAYOUT_KEY = 'min_payout';
const CATEGORY_ICON_SIZE_KEY = 'home_category_icon_size';
const CITIES_KEY = 'cities';
const LOGIN_HERO_KEY = 'login_hero_image_url';
const PAYMENT_METHODS_KEY = 'payment_methods';
const UPI_VPA_KEY = 'upi_vpa';
const UPI_PAYEE_KEY = 'upi_payee_name';
const ONBOARDING_KEYS = [
  'onboarding_image_1',
  'onboarding_image_2',
  'onboarding_image_3',
] as const;
const HOME_BANNER_KEYS = [
  'home_banner_1',
  'home_banner_2',
  'home_banner_3',
] as const;

interface PaymentMethodsValue {
  razorpay: boolean;
  upiqr: boolean;
  upigateway: boolean;
  cash: boolean;
}

function asPaymentMethods(value: unknown): PaymentMethodsValue {
  const v = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  return {
    razorpay: v.razorpay !== false,
    upiqr: v.upiqr !== false,
    upigateway: v.upigateway !== false,
    cash: v.cash !== false,
  };
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

/** The settings endpoint may return an array of settings or a flat key→value map. */
type SettingsResponse = AdminSetting[] | Record<string, unknown>;

function toMap(res: SettingsResponse | undefined): Record<string, unknown> {
  if (!res) return {};
  if (Array.isArray(res)) {
    const map: Record<string, unknown> = {};
    for (const s of res) map[s.key] = s.value;
    return map;
  }
  return res;
}

function asNumber(value: unknown, fallback = ''): string {
  if (value === null || value === undefined || value === '') return fallback;
  const n = typeof value === 'string' ? Number(value) : (value as number);
  return Number.isFinite(n) ? String(n) : fallback;
}

function asCities(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((v) => String(v)).filter(Boolean);
  if (typeof value === 'string') {
    return value
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
  }
  return [];
}

export default function SettingsPage() {
  const { data, isLoading, error, mutate } = useSWR<SettingsResponse>(
    '/settings',
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const map = useMemo(() => toMap(data), [data]);

  return (
    <div>
      <PageHeader
        eyebrow="Configuration"
        title="Settings"
        description="Platform-wide rules that take effect immediately. Each card saves on its own."
      />

      {error ? (
        <Card className="border-rose-200 bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn&rsquo;t load settings. {(error as Error)?.message}
          </p>
        </Card>
      ) : isLoading ? (
        <LoadingState label="Loading settings…" />
      ) : (
        <div className="space-y-5">
          <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <NumberSetting
            settingKey={COMMISSION_KEY}
            title="Commission rate"
            subtitle="Platform commission applied to every booking total."
            icon={<Percent className="h-5 w-5" />}
            initial={asNumber(map[COMMISSION_KEY], '20')}
            suffix="%"
            min={0}
            max={100}
            step={0.5}
            hint="Percent of the booking total. Existing bookings keep their snapshot rate."
            onSaved={mutate}
          />
          <NumberSetting
            settingKey={REFERRAL_KEY}
            title="Referral reward"
            subtitle="Wallet credit to a referrer after the referee's first completed booking."
            icon={<IndianRupee className="h-5 w-5" />}
            initial={asNumber(map[REFERRAL_KEY], '100')}
            prefix="₹"
            min={0}
            step={10}
            hint="Credited once per successful referral."
            onSaved={mutate}
          />
          <NumberSetting
            settingKey={MIN_PAYOUT_KEY}
            title="Minimum payout"
            subtitle="Smallest amount a companion may withdraw at once."
            icon={<Wallet className="h-5 w-5" />}
            initial={asNumber(map[MIN_PAYOUT_KEY], '500')}
            prefix="₹"
            min={0}
            step={50}
            hint="Withdrawal requests below this amount are rejected."
            onSaved={mutate}
          />
          <NumberSetting
            settingKey={CATEGORY_ICON_SIZE_KEY}
            title="Home category icon size"
            subtitle="How large the category icons appear on the app home screen (below the banner)."
            icon={<SlidersHorizontal className="h-5 w-5" />}
            initial={asNumber(map[CATEGORY_ICON_SIZE_KEY], '46')}
            suffix="%"
            min={30}
            max={100}
            step={1}
            hint="30–100%. Higher = bigger icons; the icon always stays inside the circle. Takes effect the next time the app opens."
            onSaved={mutate}
          />
          <CitiesSetting
            initial={asCities(map[CITIES_KEY])}
            onSaved={mutate}
          />
          <PaymentMethodsSetting
            initial={asPaymentMethods(map[PAYMENT_METHODS_KEY])}
            onSaved={mutate}
          />
          <UpiReceivingSetting
            initialVpa={asString(map[UPI_VPA_KEY])}
            initialPayee={asString(map[UPI_PAYEE_KEY])}
            onSaved={mutate}
          />
          </div>
          <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
            <ImageUploadSetting
              title="Login screen photo"
              subtitle="The couple photo on the app's login screen."
              initial={asString(map[LOGIN_HERO_KEY])}
              uploadPath="/settings/login-hero"
              deletePath="/settings/login-hero"
              onSaved={mutate}
            />
            <ImageUploadSetting
              title="Onboarding photo 1"
              subtitle="First intro step (Real-life social moments)."
              initial={asString(map[ONBOARDING_KEYS[0]])}
              uploadPath="/settings/onboarding-hero/1"
              deletePath="/settings/onboarding-hero/1"
              onSaved={mutate}
            />
            <ImageUploadSetting
              title="Onboarding photo 2"
              subtitle="Second intro step (A plus-one for everything)."
              initial={asString(map[ONBOARDING_KEYS[1]])}
              uploadPath="/settings/onboarding-hero/2"
              deletePath="/settings/onboarding-hero/2"
              onSaved={mutate}
            />
            <ImageUploadSetting
              title="Onboarding photo 3"
              subtitle="Third intro step (Safe & simple to book)."
              initial={asString(map[ONBOARDING_KEYS[2]])}
              uploadPath="/settings/onboarding-hero/3"
              deletePath="/settings/onboarding-hero/3"
              onSaved={mutate}
            />
            <ImageUploadSetting
              title="Home banner 1"
              subtitle="First promo slide on the app home carousel."
              initial={asString(map[HOME_BANNER_KEYS[0]])}
              uploadPath="/settings/home-banner/1"
              deletePath="/settings/home-banner/1"
              onSaved={mutate}
            />
            <ImageUploadSetting
              title="Home banner 2"
              subtitle="Second promo slide (optional)."
              initial={asString(map[HOME_BANNER_KEYS[1]])}
              uploadPath="/settings/home-banner/2"
              deletePath="/settings/home-banner/2"
              onSaved={mutate}
            />
            <ImageUploadSetting
              title="Home banner 3"
              subtitle="Third promo slide (optional)."
              initial={asString(map[HOME_BANNER_KEYS[2]])}
              uploadPath="/settings/home-banner/3"
              deletePath="/settings/home-banner/3"
              onSaved={mutate}
            />
          </div>
        </div>
      )}

      {/* Safety guardrail reminder — these settings never relax the core policy. */}
      <Card className="mt-5 border-brand-100 bg-brand-50/60">
        <div className="flex items-start gap-3">
          <SlidersHorizontal className="mt-0.5 h-5 w-5 shrink-0 text-brand-600" />
          <p className="text-sm text-brand-800">
            These are commercial settings only. The core safety rules — 18+ users,
            public-place meetings, companionship-only activities — are enforced in code and
            are not configurable here.
          </p>
        </div>
      </Card>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Numeric setting card (commission / referral / min payout)                   */
/* -------------------------------------------------------------------------- */

function NumberSetting({
  settingKey,
  title,
  subtitle,
  icon,
  initial,
  prefix,
  suffix,
  min,
  max,
  step,
  hint,
  onSaved,
}: {
  settingKey: string;
  title: string;
  subtitle: string;
  icon: React.ReactNode;
  initial: string;
  prefix?: string;
  suffix?: string;
  min?: number;
  max?: number;
  step?: number;
  hint?: string;
  onSaved: () => void;
}) {
  const [value, setValue] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // Re-sync when the server value loads/changes and the user hasn't edited.
  useEffect(() => {
    setValue(initial);
  }, [initial]);

  const dirty = value.trim() !== initial.trim();

  async function save() {
    const n = Number(value);
    if (value.trim() === '' || !Number.isFinite(n)) {
      setErr('Enter a valid number.');
      return;
    }
    if (min !== undefined && n < min) {
      setErr(`Must be at least ${min}.`);
      return;
    }
    if (max !== undefined && n > max) {
      setErr(`Must be at most ${max}.`);
      return;
    }
    setSaving(true);
    setErr(null);
    try {
      await apiFetch(`/settings/${settingKey}`, { method: 'PUT', body: { value: n } });
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
      onSaved();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader
        title={
          <span className="flex items-center gap-2">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-50 text-brand-600">
              {icon}
            </span>
            {title}
          </span>
        }
        subtitle={subtitle}
      />
      <div className="flex items-end gap-3">
        <Input
          type="number"
          inputMode="decimal"
          value={value}
          min={min}
          max={max}
          step={step}
          onChange={(e) => setValue(e.target.value)}
          error={err ?? undefined}
          hint={!err ? hint : undefined}
          leftIcon={prefix ? <span className="text-sm font-medium">{prefix}</span> : undefined}
          rightIcon={suffix ? <span className="text-sm font-medium">{suffix}</span> : undefined}
          containerClassName="flex-1"
          aria-label={title}
        />
        <Button
          onClick={save}
          loading={saving}
          disabled={!dirty}
          leftIcon={
            saved ? <CheckCircle2 className="h-4 w-4" /> : <Save className="h-4 w-4" />
          }
          variant={saved ? 'success' : 'primary'}
          className="mb-[1px] shrink-0"
        >
          {saved ? 'Saved' : 'Save'}
        </Button>
      </div>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* Payment methods enable/disable card                                         */
/* -------------------------------------------------------------------------- */

function MethodToggle({
  on,
  onToggle,
  label,
  sublabel,
}: {
  on: boolean;
  onToggle: (next: boolean) => void;
  label: string;
  sublabel: string;
}) {
  return (
    <div className="flex items-center justify-between gap-3 rounded-xl border border-slate-200 px-4 py-3">
      <div className="min-w-0">
        <p className="text-sm font-medium text-slate-900">{label}</p>
        <p className="text-xs text-slate-500">{sublabel}</p>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={on}
        aria-label={label}
        onClick={() => onToggle(!on)}
        className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${
          on ? 'bg-brand-600' : 'bg-slate-300'
        }`}
      >
        <span
          className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${
            on ? 'left-[22px]' : 'left-0.5'
          }`}
        />
      </button>
    </div>
  );
}

function PaymentMethodsSetting({
  initial,
  onSaved,
}: {
  initial: PaymentMethodsValue;
  onSaved: () => void;
}) {
  const [methods, setMethods] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setMethods(initial);
  }, [initial.razorpay, initial.upiqr, initial.upigateway, initial.cash]);

  const dirty =
    methods.razorpay !== initial.razorpay ||
    methods.upiqr !== initial.upiqr ||
    methods.upigateway !== initial.upigateway ||
    methods.cash !== initial.cash;
  const noneEnabled =
    !methods.razorpay && !methods.upiqr && !methods.upigateway && !methods.cash;

  async function save() {
    if (noneEnabled) {
      setErr('At least one payment method must be enabled.');
      return;
    }
    setSaving(true);
    setErr(null);
    try {
      await apiFetch(`/settings/${PAYMENT_METHODS_KEY}`, {
        method: 'PUT',
        body: { value: methods },
      });
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
      onSaved();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader
        title={
          <span className="flex items-center gap-2">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-50 text-brand-600">
              <Wallet className="h-5 w-5" />
            </span>
            Payment methods
          </span>
        }
        subtitle="Enable or disable how customers can pay for a booking."
      />
      <div className="space-y-3">
        <MethodToggle
          on={methods.upiqr}
          onToggle={(v) => setMethods((m) => ({ ...m, upiqr: v }))}
          label="UPI QR — direct to our account"
          sublabel="In-app QR to our UPI ID, auto-confirmed from the bank alert. No gateway fee. Needs the UPI ID below."
        />
        <MethodToggle
          on={methods.upigateway}
          onToggle={(v) => setMethods((m) => ({ ...m, upigateway: v }))}
          label="UPI payment page (UPIGateway)"
          sublabel="Hosted UPI checkout page opened in the browser."
        />
        <MethodToggle
          on={methods.razorpay}
          onToggle={(v) => setMethods((m) => ({ ...m, razorpay: v }))}
          label="Online payment (Razorpay)"
          sublabel="Card, UPI, netbanking — prepaid before the meeting."
        />
        <MethodToggle
          on={methods.cash}
          onToggle={(v) => setMethods((m) => ({ ...m, cash: v }))}
          label="Cash on delivery"
          sublabel="Customer pays the companion in cash at the meeting."
        />
        {err ? <p className="text-xs text-rose-600">{err}</p> : null}
        <div className="flex justify-end">
          <Button
            onClick={save}
            loading={saving}
            disabled={!dirty || noneEnabled}
            leftIcon={
              saved ? <CheckCircle2 className="h-4 w-4" /> : <Save className="h-4 w-4" />
            }
            variant={saved ? 'success' : 'primary'}
          >
            {saved ? 'Saved' : 'Save'}
          </Button>
        </div>
      </div>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* UPI receiving details (upi_vpa + upi_payee_name)                            */
/* -------------------------------------------------------------------------- */

function UpiReceivingSetting({
  initialVpa,
  initialPayee,
  onSaved,
}: {
  initialVpa: string;
  initialPayee: string;
  onSaved: () => void;
}) {
  const [vpa, setVpa] = useState(initialVpa);
  const [payee, setPayee] = useState(initialPayee);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setVpa(initialVpa);
    setPayee(initialPayee);
  }, [initialVpa, initialPayee]);

  const dirty = vpa.trim() !== initialVpa.trim() || payee.trim() !== initialPayee.trim();

  async function save() {
    const trimmedVpa = vpa.trim();
    // Basic VPA shape: something@handle (e.g. name@axl, 98765@ybl).
    if (trimmedVpa && !/^[\w.-]{2,}@[a-zA-Z]{2,}$/.test(trimmedVpa)) {
      setErr('Enter a valid UPI ID, e.g. name@axl');
      return;
    }
    setSaving(true);
    setErr(null);
    try {
      await apiFetch(`/settings/${UPI_VPA_KEY}`, {
        method: 'PUT',
        body: { value: trimmedVpa },
      });
      await apiFetch(`/settings/${UPI_PAYEE_KEY}`, {
        method: 'PUT',
        body: { value: payee.trim() },
      });
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
      onSaved();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader
        title={
          <span className="flex items-center gap-2">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-50 text-brand-600">
              <QrCode className="h-5 w-5" />
            </span>
            UPI receiving account
          </span>
        }
        subtitle="Where direct UPI QR payments land. Booking QRs are generated for this UPI ID and confirmed from the bank's credit alerts."
      />
      <div className="space-y-3">
        <Input
          label="UPI ID (VPA)"
          value={vpa}
          onChange={(e) => setVpa(e.target.value)}
          placeholder="e.g. yourname@axl"
          hint="Must be the UPI ID of the bank account whose credit alerts the mail watcher reads."
          aria-label="UPI ID"
        />
        <Input
          label="Payee name shown in UPI apps"
          value={payee}
          onChange={(e) => setPayee(e.target.value)}
          placeholder="Companion Ranchi"
          aria-label="Payee name"
        />
        {err && <p className="text-xs text-rose-600">{err}</p>}
        <div className="flex items-center justify-between">
          <Badge tone={vpa.trim() ? 'green' : 'amber'} dot>
            {vpa.trim() ? 'QR payments configured' : 'Not configured — QR disabled'}
          </Badge>
          <Button
            onClick={save}
            loading={saving}
            disabled={!dirty}
            leftIcon={
              saved ? <CheckCircle2 className="h-4 w-4" /> : <Save className="h-4 w-4" />
            }
            variant={saved ? 'success' : 'primary'}
          >
            {saved ? 'Saved' : 'Save'}
          </Button>
        </div>
      </div>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* Cities setting card (string[])                                              */
/* -------------------------------------------------------------------------- */

function CitiesSetting({
  initial,
  onSaved,
}: {
  initial: string[];
  onSaved: () => void;
}) {
  const [cities, setCities] = useState<string[]>(initial);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setCities(initial);
  }, [initial]);

  const dirty = useMemo(
    () =>
      cities.length !== initial.length ||
      cities.some((c, i) => c !== initial[i]),
    [cities, initial],
  );

  function addCity() {
    const name = draft.trim();
    if (!name) return;
    if (cities.some((c) => c.toLowerCase() === name.toLowerCase())) {
      setErr(`${name} is already listed.`);
      return;
    }
    setCities((prev) => [...prev, name]);
    setDraft('');
    setErr(null);
  }

  function removeCity(name: string) {
    setCities((prev) => prev.filter((c) => c !== name));
  }

  async function save() {
    if (cities.length === 0) {
      setErr('Add at least one city.');
      return;
    }
    setSaving(true);
    setErr(null);
    try {
      await apiFetch(`/settings/${CITIES_KEY}`, { method: 'PUT', body: { value: cities } });
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
      onSaved();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to save.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader
        title={
          <span className="flex items-center gap-2">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-50 text-brand-600">
              <MapPin className="h-5 w-5" />
            </span>
            Operating cities
          </span>
        }
        subtitle="Cities where companions can be listed and booked."
      />

      <div className="mb-3 flex flex-wrap gap-2">
        {cities.length === 0 ? (
          <span className="text-sm text-slate-400">No cities configured.</span>
        ) : (
          cities.map((city) => (
            <span
              key={city}
              className="inline-flex items-center gap-1.5 rounded-full bg-brand-50 px-3 py-1 text-sm font-medium text-brand-700"
            >
              {city}
              <button
                type="button"
                onClick={() => removeCity(city)}
                className="rounded-full p-0.5 text-brand-400 transition-colors hover:bg-brand-100 hover:text-brand-700"
                aria-label={`Remove ${city}`}
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </span>
          ))
        )}
      </div>

      <div className="flex items-end gap-2">
        <Input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              addCity();
            }
          }}
          placeholder="Add a city, e.g. Jamshedpur"
          error={err ?? undefined}
          leftIcon={<MapPin className="h-4 w-4" />}
          containerClassName="flex-1"
          aria-label="New city"
        />
        <Button
          variant="outline"
          onClick={addCity}
          leftIcon={<Plus className="h-4 w-4" />}
          className="mb-[1px] shrink-0"
        >
          Add
        </Button>
      </div>

      <div className="mt-4 flex items-center justify-between">
        <Badge tone="gray">
          {cities.length} {cities.length === 1 ? 'city' : 'cities'}
        </Badge>
        <Button
          onClick={save}
          loading={saving}
          disabled={!dirty}
          leftIcon={
            saved ? <CheckCircle2 className="h-4 w-4" /> : <Save className="h-4 w-4" />
          }
          variant={saved ? 'success' : 'primary'}
        >
          {saved ? 'Saved' : 'Save cities'}
        </Button>
      </div>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* Mobile app photo (login hero / onboarding steps)                            */
/* -------------------------------------------------------------------------- */

function ImageUploadSetting({
  title,
  subtitle,
  initial,
  uploadPath,
  deletePath,
  onSaved,
}: {
  title: string;
  subtitle: string;
  initial: string;
  /** Admin API path (relative to /api/admin) that accepts a multipart "image". */
  uploadPath: string;
  /** Admin API path for DELETE to clear the photo. */
  deletePath: string;
  onSaved: () => void;
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [url, setUrl] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setUrl(initial);
  }, [initial]);

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = ''; // allow re-selecting the same file
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      setErr('Please choose an image file.');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      setErr('Image must be under 5 MB.');
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      const form = new FormData();
      form.append('image', file);
      const res = await fetch(`${ADMIN_API_BASE}${uploadPath}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${getToken() ?? ''}` },
        body: form,
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as
          | { error?: { message?: string } }
          | null;
        throw new Error(body?.error?.message || `Upload failed (${res.status}).`);
      }
      const body = (await res.json()) as { data?: { url?: string } };
      setUrl(body?.data?.url ?? '');
      setSaved(true);
      setTimeout(() => setSaved(false), 2500);
      onSaved();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Upload failed.');
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    setBusy(true);
    setErr(null);
    try {
      await apiFetch(deletePath, { method: 'DELETE' });
      setUrl('');
      onSaved();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to remove.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardHeader
        title={
          <span className="flex items-center gap-2">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-50 text-brand-600">
              <ImageIcon className="h-5 w-5" />
            </span>
            {title}
          </span>
        }
        subtitle={`${subtitle} Changes go live immediately — no app update needed.`}
      />

      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={onFile}
      />

      <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
        <div className="relative h-32 w-full overflow-hidden rounded-xl border-2 border-ink bg-brand-50 sm:w-56">
          {url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={url} alt={title} className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full w-full items-center justify-center px-4 text-center text-sm text-slate-400">
              Using the app&rsquo;s built-in photo
            </div>
          )}
        </div>

        <div className="flex flex-1 flex-col items-start gap-2">
          <Button
            onClick={() => fileInputRef.current?.click()}
            loading={busy}
            leftIcon={<ImagePlus className="h-4 w-4" />}
          >
            {url ? 'Replace photo' : 'Upload photo'}
          </Button>
          {url ? (
            <Button
              variant="outline"
              onClick={remove}
              disabled={busy}
              leftIcon={<Trash2 className="h-4 w-4" />}
            >
              Remove
            </Button>
          ) : null}
          <p className="text-xs text-slate-500">
            A wide (landscape) image works best. JPG or PNG, under 5&nbsp;MB.
          </p>
          {err ? <p className="text-sm text-rose-600">{err}</p> : null}
          {saved ? (
            <p className="flex items-center gap-1.5 text-sm text-emerald-600">
              <CheckCircle2 className="h-4 w-4" /> Saved — live on the app.
            </p>
          ) : null}
        </div>
      </div>
    </Card>
  );
}
