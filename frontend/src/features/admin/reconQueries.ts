import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export interface WarehouseCountRow {
  source_object: string
  country:       string | null
  year:          number | null
  row_count:     number
}

export function useWarehouseCounts() {
  return useQuery({
    queryKey: ['admin', 'warehouse-counts'],
    queryFn: async () => {
      const { data, error } = await supabase.schema('rep_portal').rpc('get_warehouse_counts')
      if (error) throw error
      return data as WarehouseCountRow[]
    },
    staleTime: 5 * 60 * 1000,
  })
}
