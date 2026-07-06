'use client';

/**
 * Admin → Categories
 *
 * Activity categories used across the marketplace. Admins manage the icon
 * image shown for each category. Images are stored in Cloudinary on the
 * backend; this page only uploads/clears them.
 *
 * Backed by:
 *   GET    /admin/categories
 *   POST   /admin/categories/:id/icon   (multipart/form-data, field `image`)
 *   DELETE /admin/categories/:id/icon
 *
 * (Routes/fields match docs/API.md → ADMIN API.)
 */

import { useRef, useState } from 'react';
import useSWR from 'swr';
import { ImagePlus, Info, Trash2 } from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { ADMIN_API_BASE, apiFetch, apiFetchList, ApiError, getToken } from '@/lib/api';
import type { Category } from '@/lib/types';

export default function CategoriesPage() {
  // Per-row inline action loading (upload / remove).
  const [busyId, setBusyId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  // Category whose icon a click is about to replace via the file picker.
  const [targetId, setTargetId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data, isLoading, error, mutate } = useSWR<Category[]>(
    '/categories',
    (path: string) => apiFetchList<Category[]>(path).then((r) => r.data ?? []),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data ?? [];

  function openFilePicker(category: Category) {
    setTargetId(category.id);
    setActionError(null);
    fileInputRef.current?.click();
  }

  async function onFileSelected(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    const id = targetId;
    // Reset the input so picking the same file again still fires onChange.
    e.target.value = '';
    setTargetId(null);
    if (!file || !id) return;

    setBusyId(id);
    setActionError(null);
    try {
      const form = new FormData();
      form.append('image', file);
      const res = await fetch(`${ADMIN_API_BASE}/categories/${id}/icon`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${getToken() ?? ''}` },
        body: form,
      });
      if (!res.ok) {
        let message = `Upload failed (${res.status}).`;
        try {
          const body = (await res.json()) as { error?: { message?: string } };
          if (body?.error?.message) message = body.error.message;
        } catch {
          /* non-JSON error body */
        }
        throw new Error(message);
      }
      await mutate();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Failed to upload icon.');
    } finally {
      setBusyId(null);
    }
  }

  async function removeIcon(category: Category) {
    setBusyId(category.id);
    setActionError(null);
    try {
      await apiFetch(`/categories/${category.id}/icon`, { method: 'DELETE' });
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to remove icon.');
    } finally {
      setBusyId(null);
    }
  }

  const columns: Column<Category>[] = [
    {
      key: 'icon',
      header: 'Icon',
      render: (c) =>
        c.iconUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={c.iconUrl}
            alt={c.name}
            className="h-10 w-10 rounded-lg object-cover ring-1 ring-slate-200"
          />
        ) : (
          <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-50 text-slate-300 ring-1 ring-slate-200">
            —
          </span>
        ),
    },
    {
      key: 'name',
      header: 'Name',
      render: (c) => <span className="font-medium text-slate-900">{c.name}</span>,
    },
    {
      key: 'slug',
      header: 'Slug',
      hideOnMobile: true,
      accessor: (c) => <span className="text-slate-500">{c.slug}</span>,
    },
    {
      key: 'order',
      header: 'Order',
      align: 'center',
      hideOnMobile: true,
      accessor: (c) => <span className="text-slate-600">{c.sortOrder ?? '—'}</span>,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (c) => (
        <div className="flex items-center justify-end gap-1.5">
          <Button
            size="sm"
            variant="outline"
            loading={busyId === c.id}
            onClick={() => openFilePicker(c)}
            leftIcon={<ImagePlus className="h-3.5 w-3.5" />}
          >
            Upload icon
          </Button>
          {c.iconUrl && (
            <Button
              size="sm"
              variant="ghost"
              disabled={busyId === c.id}
              onClick={() => removeIcon(c)}
              leftIcon={<Trash2 className="h-3.5 w-3.5" />}
            >
              Remove
            </Button>
          )}
        </div>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Catalog"
        title="Activity Categories"
        description="Manage the activity categories shown across the marketplace and upload an icon image for each."
      />

      {/* Hidden file input shared by every row's "Upload icon" button. */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={onFileSelected}
      />

      <Card className="mb-4 border-brand-100 bg-brand-50/60">
        <p className="flex items-start gap-2 text-sm text-brand-700">
          <Info className="mt-0.5 h-4 w-4 shrink-0" />
          Images are stored in Cloudinary. If uploads fail, ensure CLOUDINARY_URL is configured
          on the backend.
        </p>
      </Card>

      {actionError && (
        <Card className="mb-4 border-rose-200 bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-rose-200 bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load categories. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(c) => c.id}
          loading={isLoading}
          emptyMessage="No categories found."
        />
      )}
    </div>
  );
}
