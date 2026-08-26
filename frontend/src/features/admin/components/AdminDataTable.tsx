import { Fragment, useMemo, useState, type ReactNode } from 'react'
import { usePagination, Pagination, PAGE_SIZE } from '../Pagination'
import { RowActionsMenu, type RowAction } from './RowActionsMenu'

// Shared flat-row admin table: owns pagination, sort, empty/loading/error
// states, and row actions/expansion — the pieces duplicated (or missing)
// across most admin/*.tsx tables. Search inputs and filter dropdowns stay
// page-owned (rendered above this component) since their shape differs too
// much per page to usefully abstract; this component only takes the
// already-filtered `data` array.

export interface AdminColumn<T> {
  key: string
  header: ReactNode
  render: (row: T) => ReactNode
  /** Omit to make the column unsortable. Return null to sort it last. */
  sortValue?: (row: T) => string | number | null
  /** Marks a column sortable without a client-side sortValue — for use with the controlled `sort` prop (server-side sort). */
  sortable?: boolean
  align?: 'left' | 'right'
  /** Fixed column width (e.g. '20%'). Only needed for tables with long, wrappable cell content. */
  width?: string
}

export interface ServerPaginationInfo {
  page: number
  totalPages: number
  total: number
  onPage: (page: number) => void
}

export interface AdminDataTableProps<T> {
  data: T[]
  rowKey: (row: T) => string | number
  columns: AdminColumn<T>[]
  isLoading?: boolean
  error?: unknown
  emptyMessage?: string
  loadingMessage?: string
  /** Client-side page size. Ignored when `serverPagination` is provided. */
  pageSize?: number
  /** When provided, `data` is assumed to already be just the current page — no client-side slicing or sorting happens. */
  serverPagination?: ServerPaginationInfo
  /** Controlled server-side sort. When provided, header clicks call `onChange` instead of sorting client-side. */
  sort?: { key?: string; dir: 'asc' | 'desc'; onChange: (key: string) => void }
  onRowClick?: (row: T) => void
  rowActions?: (row: T) => RowAction[]
  /** Renders a full-width detail row under a given row when expanded. */
  renderExpanded?: (row: T) => ReactNode
  /** Whether a given row shows the expand toggle at all. Defaults to always, when `renderExpanded` is set. */
  canExpand?: (row: T) => boolean
  defaultSortKey?: string
  defaultSortDir?: 'asc' | 'desc'
}

export function AdminDataTable<T>({
  data,
  rowKey,
  columns,
  isLoading,
  error,
  emptyMessage = 'No records found.',
  loadingMessage = 'Loading…',
  pageSize = PAGE_SIZE,
  serverPagination,
  sort,
  onRowClick,
  rowActions,
  renderExpanded,
  canExpand,
  defaultSortKey,
  defaultSortDir = 'asc',
}: AdminDataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | undefined>(defaultSortKey)
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>(defaultSortDir)
  const [expandedKey, setExpandedKey] = useState<string | number | null>(null)

  const sorted = useMemo(() => {
    if (serverPagination || !sortKey) return data
    const col = columns.find((c) => c.key === sortKey)
    if (!col?.sortValue) return data
    const dir = sortDir === 'asc' ? 1 : -1
    return [...data].sort((a, b) => {
      const av = col.sortValue!(a)
      const bv = col.sortValue!(b)
      if (av == null && bv == null) return 0
      if (av == null) return 1
      if (bv == null) return -1
      if (av < bv) return -1 * dir
      if (av > bv) return 1 * dir
      return 0
    })
  }, [data, sortKey, sortDir, columns, serverPagination])

  const client = usePagination(serverPagination ? undefined : sorted, pageSize)
  const pageData = serverPagination ? data : client.pageData
  const pagination = serverPagination ?? { page: client.page, totalPages: client.totalPages, total: client.total, onPage: client.setPage }

  function toggleSort(col: AdminColumn<T>) {
    if (!col.sortValue && !col.sortable) return
    if (sort) {
      sort.onChange(col.key)
      return
    }
    if (sortKey === col.key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    } else {
      setSortKey(col.key)
      setSortDir('asc')
    }
  }

  const activeSortKey = sort ? sort.key : sortKey
  const activeSortDir = sort ? sort.dir : sortDir

  if (isLoading) return <div className="admin-loading">{loadingMessage}</div>
  if (error) return <div className="admin-error">{error instanceof Error ? error.message : 'Failed to load data.'}</div>
  if (data.length === 0) return <div className="admin-empty">{emptyMessage}</div>

  const hasActions = !!rowActions
  const hasExpand = !!renderExpanded
  const hasWidths = columns.some((c) => c.width)

  return (
    <>
      <div className="admin-table-wrap">
        <table className="admin-table" style={hasWidths ? { tableLayout: 'fixed', width: '100%' } : undefined}>
          {hasWidths && (
            <colgroup>
              {hasExpand && <col style={{ width: 40 }} />}
              {columns.map((col) => <col key={col.key} style={{ width: col.width }} />)}
              {hasActions && <col style={{ width: 60 }} />}
            </colgroup>
          )}
          <thead>
            <tr>
              {hasExpand && <th />}
              {columns.map((col) => {
                const sortable = !!col.sortValue || !!col.sortable
                return (
                  <th
                    key={col.key}
                    style={{ textAlign: col.align === 'right' ? 'right' : undefined, cursor: sortable ? 'pointer' : undefined }}
                    onClick={() => toggleSort(col)}
                    title={sortable ? 'Click to sort' : undefined}
                  >
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                      {col.header}
                      {sortable && (
                        <span style={{ fontSize: '0.7em', opacity: activeSortKey === col.key ? 1 : 0.35 }}>
                          {activeSortKey === col.key ? (activeSortDir === 'asc' ? '▲' : '▼') : '⇅'}
                        </span>
                      )}
                    </span>
                  </th>
                )
              })}
              {hasActions && <th />}
            </tr>
          </thead>
          <tbody>
            {pageData.map((row) => {
              const key = rowKey(row)
              const expandable = hasExpand && (canExpand ? canExpand(row) : true)
              const isExpanded = expandedKey === key
              return (
                <Fragment key={key}>
                  <tr
                    className={isExpanded ? 'admin-table-row--expanded' : ''}
                    style={onRowClick ? { cursor: 'pointer' } : undefined}
                    onClick={onRowClick ? () => onRowClick(row) : undefined}
                  >
                    {hasExpand && (
                      <td>
                        {expandable && (
                          <button
                            className="admin-expand-btn"
                            onClick={(e) => { e.stopPropagation(); setExpandedKey(isExpanded ? null : key) }}
                          >
                            {isExpanded ? '▲' : '▼'}
                          </button>
                        )}
                      </td>
                    )}
                    {columns.map((col) => (
                      <td key={col.key} style={{ textAlign: col.align === 'right' ? 'right' : undefined }}>
                        {col.render(row)}
                      </td>
                    ))}
                    {hasActions && (
                      <td className="admin-table-actions" onClick={(e) => e.stopPropagation()}>
                        <RowActionsMenu actions={rowActions!(row)} />
                      </td>
                    )}
                  </tr>
                  {isExpanded && (
                    <tr key={`${key}-detail`}>
                      <td colSpan={columns.length + (hasExpand ? 1 : 0) + (hasActions ? 1 : 0)} className="admin-table-detail">
                        {renderExpanded!(row)}
                      </td>
                    </tr>
                  )}
                </Fragment>
              )
            })}
          </tbody>
        </table>
      </div>
      <Pagination page={pagination.page} totalPages={pagination.totalPages} total={pagination.total} pageSize={pageSize} onPage={pagination.onPage} />
    </>
  )
}
