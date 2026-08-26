import { useState } from 'react'

export function fmt(iso: string): string {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

export const PAGE_SIZE = 10

export function usePagination<T>(data: T[] | undefined, pageSize = PAGE_SIZE) {
  const [page, setPage] = useState(1)
  const total = data?.length ?? 0
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  const safePage = Math.min(page, totalPages)
  const pageData = data?.slice((safePage - 1) * pageSize, safePage * pageSize) ?? []

  function goTo(p: number) {
    setPage(Math.max(1, Math.min(p, totalPages)))
  }

  return { page: safePage, setPage: goTo, pageData, totalPages, total }
}

export function Pagination({
  page,
  totalPages,
  total,
  pageSize,
  onPage,
}: {
  page: number
  totalPages: number
  total: number
  pageSize: number
  onPage: (p: number) => void
}) {
  if (totalPages <= 1) return null
  const from = (page - 1) * pageSize + 1
  const to = Math.min(page * pageSize, total)

  return (
    <div className="admin-pagination">
      <span className="admin-pagination-info">{from}–{to} of {total}</span>
      <button
        className="admin-btn admin-btn--sm"
        disabled={page === 1}
        onClick={() => onPage(page - 1)}
      >
        ‹ Prev
      </button>
      <span className="admin-pagination-page">{page} / {totalPages}</span>
      <button
        className="admin-btn admin-btn--sm"
        disabled={page === totalPages}
        onClick={() => onPage(page + 1)}
      >
        Next ›
      </button>
    </div>
  )
}
