export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      schools: {
        Row: {
          active_partner_school: boolean | null
          country_name: string | null
          country_slug: string | null
          district_name: string | null
          geo_source: string | null
          kpis: Json | null
          latitude: number | null
          longitude: number | null
          province: string | null
          school_id: string
          school_name: string
        }
        Insert: {
          active_partner_school?: boolean | null
          country_name?: string | null
          country_slug?: string | null
          district_name?: string | null
          geo_source?: string | null
          kpis?: Json | null
          latitude?: number | null
          longitude?: number | null
          province?: string | null
          school_id: string
          school_name: string
        }
        Update: {
          active_partner_school?: boolean | null
          country_name?: string | null
          country_slug?: string | null
          district_name?: string | null
          geo_source?: string | null
          kpis?: Json | null
          latitude?: number | null
          longitude?: number | null
          province?: string | null
          school_id?: string
          school_name?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_observed_kpi: {
        Args: { p_kpi_id: string }
        Returns: {
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          kpi_id: string
          row_scope: string
          value: string
          year: number
          year_quarter: number
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  rep_portal: {
    Tables: {
      dashboard_data_agg: {
        Row: {
          country: string | null
          district: string | null
          metric: string
          province: string | null
          school: string | null
          school_type: string | null
          value: number
          year: number | null
        }
        Insert: {
          country?: string | null
          district?: string | null
          metric: string
          province?: string | null
          school?: string | null
          school_type?: string | null
          value?: number
          year?: number | null
        }
        Update: {
          country?: string | null
          district?: string | null
          metric?: string
          province?: string | null
          school?: string | null
          school_type?: string | null
          value?: number
          year?: number | null
        }
        Relationships: []
      }
      dashboards: {
        Row: {
          created_at: string
          display_order: number
          id: number
          is_default: boolean
          key: string
          label: string
          source_type: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: number
          is_default?: boolean
          key: string
          label: string
          source_type: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: number
          is_default?: boolean
          key?: string
          label?: string
          source_type?: string
          updated_at?: string
        }
        Relationships: []
      }
      dashlet_categories: {
        Row: {
          created_at: string
          dashboard_id: number
          description: string | null
          display_order: number
          display_title: string | null
          id: number
          is_uncategorized: boolean
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          dashboard_id: number
          description?: string | null
          display_order?: number
          display_title?: string | null
          id?: number
          is_uncategorized?: boolean
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          dashboard_id?: number
          description?: string | null
          display_order?: number
          display_title?: string | null
          id?: number
          is_uncategorized?: boolean
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dashlet_categories_dashboard_id_fkey"
            columns: ["dashboard_id"]
            isOneToOne: false
            referencedRelation: "dashboards"
            referencedColumns: ["id"]
          },
        ]
      }
      dashlet_comments: {
        Row: {
          comment: string | null
          created_at: string
          id: number
          is_enabled: boolean
          permission_key: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          comment?: string | null
          created_at?: string
          id?: number
          is_enabled?: boolean
          permission_key: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          comment?: string | null
          created_at?: string
          id?: number
          is_enabled?: boolean
          permission_key?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "dashlet_comments_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: true
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
        ]
      }
      dashlet_drafts: {
        Row: {
          chart_type: string | null
          comment: string | null
          comment_enabled: boolean
          created_at: string
          description: string | null
          display_mode: string | null
          group_id: number | null
          kpi_disagg1_filters: string[]
          kpi_disagg2_filters: string[]
          kpi_id: string | null
          kpi_split_mode: string | null
          label: string
          metric_config_ids: number[]
          parent_key: string | null
          permission_key: string
          show_milestone: boolean
          source_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          chart_type?: string | null
          comment?: string | null
          comment_enabled?: boolean
          created_at?: string
          description?: string | null
          display_mode?: string | null
          group_id?: number | null
          kpi_disagg1_filters?: string[]
          kpi_disagg2_filters?: string[]
          kpi_id?: string | null
          kpi_split_mode?: string | null
          label: string
          metric_config_ids?: number[]
          parent_key?: string | null
          permission_key: string
          show_milestone?: boolean
          source_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          chart_type?: string | null
          comment?: string | null
          comment_enabled?: boolean
          created_at?: string
          description?: string | null
          display_mode?: string | null
          group_id?: number | null
          kpi_disagg1_filters?: string[]
          kpi_disagg2_filters?: string[]
          kpi_id?: string | null
          kpi_split_mode?: string | null
          label?: string
          metric_config_ids?: number[]
          parent_key?: string | null
          permission_key?: string
          show_milestone?: boolean
          source_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "dashlet_drafts_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "dashlet_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dashlet_drafts_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: true
            referencedRelation: "dashlets"
            referencedColumns: ["permission_key"]
          },
        ]
      }
      dashlet_groups: {
        Row: {
          category_id: number | null
          created_at: string
          dashboard_id: number
          display_order: number
          id: number
          is_ungrouped: boolean
          name: string
          source_type: string
          updated_at: string
        }
        Insert: {
          category_id?: number | null
          created_at?: string
          dashboard_id: number
          display_order?: number
          id?: number
          is_ungrouped?: boolean
          name: string
          source_type?: string
          updated_at?: string
        }
        Update: {
          category_id?: number | null
          created_at?: string
          dashboard_id?: number
          display_order?: number
          id?: number
          is_ungrouped?: boolean
          name?: string
          source_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dashlet_groups_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "dashlet_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dashlet_groups_dashboard_id_fkey"
            columns: ["dashboard_id"]
            isOneToOne: false
            referencedRelation: "dashboards"
            referencedColumns: ["id"]
          },
        ]
      }
      dashlet_kpi_config: {
        Row: {
          dashlet_id: number
          kpi_disagg1_filters: string[]
          kpi_disagg2_filters: string[]
          kpi_id: string
          kpi_split_mode: string
          show_milestone: boolean
        }
        Insert: {
          dashlet_id: number
          kpi_disagg1_filters?: string[]
          kpi_disagg2_filters?: string[]
          kpi_id: string
          kpi_split_mode?: string
          show_milestone?: boolean
        }
        Update: {
          dashlet_id?: number
          kpi_disagg1_filters?: string[]
          kpi_disagg2_filters?: string[]
          kpi_id?: string
          kpi_split_mode?: string
          show_milestone?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "dashlet_kpi_config_dashlet_id_fkey"
            columns: ["dashlet_id"]
            isOneToOne: true
            referencedRelation: "dashlets"
            referencedColumns: ["id"]
          },
        ]
      }
      dashlet_metric_configs: {
        Row: {
          dashlet_id: number
          metric_config_id: number
        }
        Insert: {
          dashlet_id: number
          metric_config_id: number
        }
        Update: {
          dashlet_id?: number
          metric_config_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "dashlet_metric_configs_dashlet_id_fkey"
            columns: ["dashlet_id"]
            isOneToOne: false
            referencedRelation: "dashlets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dashlet_metric_configs_metric_config_id_fkey"
            columns: ["metric_config_id"]
            isOneToOne: false
            referencedRelation: "metric_config"
            referencedColumns: ["id"]
          },
        ]
      }
      dashlets: {
        Row: {
          chart_type: string | null
          comment: string | null
          comment_enabled: boolean
          created_at: string
          dashboard_id: number
          display_mode: string | null
          group_id: number | null
          id: number
          permission_key: string
          source_type: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          chart_type?: string | null
          comment?: string | null
          comment_enabled?: boolean
          created_at?: string
          dashboard_id: number
          display_mode?: string | null
          group_id?: number | null
          id?: number
          permission_key: string
          source_type?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          chart_type?: string | null
          comment?: string | null
          comment_enabled?: boolean
          created_at?: string
          dashboard_id?: number
          display_mode?: string | null
          group_id?: number | null
          id?: number
          permission_key?: string
          source_type?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "dashlets_dashboard_id_fkey"
            columns: ["dashboard_id"]
            isOneToOne: false
            referencedRelation: "dashboards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dashlets_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "dashlet_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dashlets_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: true
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
        ]
      }
      data_dictionary: {
        Row: {
          created_at: string
          definition: string | null
          id: number
          kpi_group: string | null
          kpi_id: string
          kpi_name: string
          kpi_number: string | null
        }
        Insert: {
          created_at?: string
          definition?: string | null
          id?: number
          kpi_group?: string | null
          kpi_id: string
          kpi_name: string
          kpi_number?: string | null
        }
        Update: {
          created_at?: string
          definition?: string | null
          id?: number
          kpi_group?: string | null
          kpi_id?: string
          kpi_name?: string
          kpi_number?: string | null
        }
        Relationships: []
      }
      entity_history: {
        Row: {
          change_type: string
          changed_at: string
          changed_by: string | null
          entity_key: string
          entity_type: string
          id: number
          snapshot: Json
        }
        Insert: {
          change_type: string
          changed_at?: string
          changed_by?: string | null
          entity_key: string
          entity_type: string
          id?: number
          snapshot: Json
        }
        Update: {
          change_type?: string
          changed_at?: string
          changed_by?: string | null
          entity_key?: string
          entity_type?: string
          id?: number
          snapshot?: Json
        }
        Relationships: []
      }
      ip_targets: {
        Row: {
          country: string
          disagg_level_one: string | null
          disagg_level_two: string | null
          id: number
          indicator: string
          indicator_code: string
          target_value: number | null
          year: number
        }
        Insert: {
          country: string
          disagg_level_one?: string | null
          disagg_level_two?: string | null
          id?: number
          indicator: string
          indicator_code: string
          target_value?: number | null
          year: number
        }
        Update: {
          country?: string
          disagg_level_one?: string | null
          disagg_level_two?: string | null
          id?: number
          indicator?: string
          indicator_code?: string
          target_value?: number | null
          year?: number
        }
        Relationships: []
      }
      kpi_mapping: {
        Row: {
          dashboard_page: string
          dashlet_element: number
          data_element: string
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number
          is_cumulative: boolean
          kpi_id: string
          source_table: string
          toggle: string | null
        }
        Insert: {
          dashboard_page: string
          dashlet_element: number
          data_element: string
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          id?: number
          is_cumulative?: boolean
          kpi_id: string
          source_table?: string
          toggle?: string | null
        }
        Update: {
          dashboard_page?: string
          dashlet_element?: number
          data_element?: string
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          id?: number
          is_cumulative?: boolean
          kpi_id?: string
          source_table?: string
          toggle?: string | null
        }
        Relationships: []
      }
      kpi_milestone_chart_visibility: {
        Row: {
          chart_key: string
          is_visible: boolean
          updated_at: string
        }
        Insert: {
          chart_key: string
          is_visible?: boolean
          updated_at?: string
        }
        Update: {
          chart_key?: string
          is_visible?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      kpi_trend_chart_visibility: {
        Row: {
          chart_key: string
          is_visible: boolean
          updated_at: string
        }
        Insert: {
          chart_key: string
          is_visible?: boolean
          updated_at?: string
        }
        Update: {
          chart_key?: string
          is_visible?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      metric_config: {
        Row: {
          created_at: string
          enabled: boolean
          filters: Json | null
          geography_level: string
          id: number
          metric_name: string
          sort_order: number | null
          source_view: string
          value_agg: string
          value_field: string | null
          year_field: string
        }
        Insert: {
          created_at?: string
          enabled?: boolean
          filters?: Json | null
          geography_level?: string
          id?: number
          metric_name: string
          sort_order?: number | null
          source_view: string
          value_agg?: string
          value_field?: string | null
          year_field?: string
        }
        Update: {
          created_at?: string
          enabled?: boolean
          filters?: Json | null
          geography_level?: string
          id?: number
          metric_name?: string
          sort_order?: number | null
          source_view?: string
          value_agg?: string
          value_field?: string | null
          year_field?: string
        }
        Relationships: []
      }
      permission_metric_config_map: {
        Row: {
          metric_config_id: number
          permission_key: string
        }
        Insert: {
          metric_config_id: number
          permission_key: string
        }
        Update: {
          metric_config_id?: number
          permission_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "permission_metric_config_map_metric_config_id_fkey"
            columns: ["metric_config_id"]
            isOneToOne: false
            referencedRelation: "metric_config"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "permission_metric_config_map_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
        ]
      }
      permissions: {
        Row: {
          category: string
          description: string | null
          id: number
          key: string
          label: string
          parent_key: string | null
        }
        Insert: {
          category: string
          description?: string | null
          id?: number
          key: string
          label: string
          parent_key?: string | null
        }
        Update: {
          category?: string
          description?: string | null
          id?: number
          key?: string
          label?: string
          parent_key?: string | null
        }
        Relationships: []
      }
      portal_page_views: {
        Row: {
          id: number
          occurred_at: string
          page: string
          user_email: string | null
          user_id: string
        }
        Insert: {
          id?: number
          occurred_at?: string
          page: string
          user_email?: string | null
          user_id: string
        }
        Update: {
          id?: number
          occurred_at?: string
          page?: string
          user_email?: string | null
          user_id?: string
        }
        Relationships: []
      }
      portal_usage_monthly: {
        Row: {
          page: string
          usage_month: string
          user_email: string | null
          user_id: string
          view_count: number
        }
        Insert: {
          page: string
          usage_month: string
          user_email?: string | null
          user_id: string
          view_count: number
        }
        Update: {
          page?: string
          usage_month?: string
          user_email?: string | null
          user_id?: string
          view_count?: number
        }
        Relationships: []
      }
      report_config: {
        Row: {
          created_at: string
          geography_level: string
          label: string
          report_key: string
          sort_order: number
          source_view: string
          year_field: string
        }
        Insert: {
          created_at?: string
          geography_level: string
          label: string
          report_key: string
          sort_order?: number
          source_view: string
          year_field: string
        }
        Update: {
          created_at?: string
          geography_level?: string
          label?: string
          report_key?: string
          sort_order?: number
          source_view?: string
          year_field?: string
        }
        Relationships: []
      }
      report_dimension_config: {
        Row: {
          column_name: string
          created_at: string
          enabled: boolean
          id: number
          label: string
          report_key: string
          sort_order: number
        }
        Insert: {
          column_name: string
          created_at?: string
          enabled?: boolean
          id?: number
          label: string
          report_key: string
          sort_order?: number
        }
        Update: {
          column_name?: string
          created_at?: string
          enabled?: boolean
          id?: number
          label?: string
          report_key?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "report_dimension_config_report_key_fkey"
            columns: ["report_key"]
            isOneToOne: false
            referencedRelation: "report_config"
            referencedColumns: ["report_key"]
          },
        ]
      }
      report_measure_config: {
        Row: {
          agg_type: string
          column_name: string | null
          created_at: string
          enabled: boolean
          id: number
          label: string
          report_key: string
          sort_order: number
        }
        Insert: {
          agg_type: string
          column_name?: string | null
          created_at?: string
          enabled?: boolean
          id?: number
          label: string
          report_key: string
          sort_order?: number
        }
        Update: {
          agg_type?: string
          column_name?: string | null
          created_at?: string
          enabled?: boolean
          id?: number
          label?: string
          report_key?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "report_measure_config_report_key_fkey"
            columns: ["report_key"]
            isOneToOne: false
            referencedRelation: "report_config"
            referencedColumns: ["report_key"]
          },
        ]
      }
      role_permissions: {
        Row: {
          permission_id: number
          role_id: number
        }
        Insert: {
          permission_id: number
          role_id: number
        }
        Update: {
          permission_id?: number
          role_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          id: number
          name: string
          updated_at: string
          whatsapp_available: boolean
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: number
          name: string
          updated_at?: string
          whatsapp_available?: boolean
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: number
          name?: string
          updated_at?: string
          whatsapp_available?: boolean
        }
        Relationships: []
      }
      user_countries: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          country: string
          id: number
          user_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          country: string
          id?: number
          user_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          country?: string
          id?: number
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          role_id: number
          user_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          role_id: number
          user_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          role_id?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_approver_districts: {
        Row: {
          assigned_at: string
          district_id: string
          district_name: string
          id: number
          whatsapp_user_id: number
        }
        Insert: {
          assigned_at?: string
          district_id: string
          district_name: string
          id?: number
          whatsapp_user_id: number
        }
        Update: {
          assigned_at?: string
          district_id?: string
          district_name?: string
          id?: number
          whatsapp_user_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_approver_districts_whatsapp_user_id_fkey"
            columns: ["whatsapp_user_id"]
            isOneToOne: false
            referencedRelation: "whatsapp_users"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_bot_sessions: {
        Row: {
          consented_at: string | null
          context: Json
          id: number
          last_approver_reminder_at: string | null
          phone: string
          step: string
          updated_at: string
        }
        Insert: {
          consented_at?: string | null
          context?: Json
          id?: number
          last_approver_reminder_at?: string | null
          phone: string
          step?: string
          updated_at?: string
        }
        Update: {
          consented_at?: string | null
          context?: Json
          id?: number
          last_approver_reminder_at?: string | null
          phone?: string
          step?: string
          updated_at?: string
        }
        Relationships: []
      }
      whatsapp_district_access: {
        Row: {
          approver_id: number | null
          created_at: string
          decided_at: string | null
          district_id: string
          district_name: string
          id: number
          rejection_reason: string | null
          requester_id: number
          status: string
          updated_at: string
        }
        Insert: {
          approver_id?: number | null
          created_at?: string
          decided_at?: string | null
          district_id: string
          district_name: string
          id?: number
          rejection_reason?: string | null
          requester_id: number
          status?: string
          updated_at?: string
        }
        Update: {
          approver_id?: number | null
          created_at?: string
          decided_at?: string | null
          district_id?: string
          district_name?: string
          id?: number
          rejection_reason?: string | null
          requester_id?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_district_access_approver_id_fkey"
            columns: ["approver_id"]
            isOneToOne: false
            referencedRelation: "whatsapp_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whatsapp_district_access_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "whatsapp_users"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_events: {
        Row: {
          flow: string
          from_step: string | null
          id: number
          occurred_at: string
          outcome: string | null
          phone_hash: string
          to_step: string
          user_id: number | null
        }
        Insert: {
          flow: string
          from_step?: string | null
          id?: number
          occurred_at?: string
          outcome?: string | null
          phone_hash: string
          to_step: string
          user_id?: number | null
        }
        Update: {
          flow?: string
          from_step?: string | null
          id?: number
          occurred_at?: string
          outcome?: string | null
          phone_hash?: string
          to_step?: string
          user_id?: number | null
        }
        Relationships: []
      }
      whatsapp_users: {
        Row: {
          consented_at: string | null
          created_at: string
          email: string | null
          id: number
          is_approver: boolean
          linked_at: string | null
          name: string | null
          phone: string
          portal_id: string
          role_id: number | null
          supabase_user_id: string | null
          updated_at: string
        }
        Insert: {
          consented_at?: string | null
          created_at?: string
          email?: string | null
          id?: number
          is_approver?: boolean
          linked_at?: string | null
          name?: string | null
          phone: string
          portal_id?: string
          role_id?: number | null
          supabase_user_id?: string | null
          updated_at?: string
        }
        Update: {
          consented_at?: string | null
          created_at?: string
          email?: string | null
          id?: number
          is_approver?: boolean
          linked_at?: string | null
          name?: string | null
          phone?: string
          portal_id?: string
          role_id?: number | null
          supabase_user_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_users_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      kpi_coverage_data: {
        Row: {
          country: string | null
          indicator: string | null
          kpi_group: string | null
          kpi_id: string | null
          row_scope: string | null
          updated_date: string | null
          value: string | null
          year: number | null
        }
        Relationships: []
      }
      view_usage_by_page: {
        Row: {
          page: string | null
          total_views: number | null
          unique_users: number | null
        }
        Relationships: []
      }
      view_usage_by_user: {
        Row: {
          dashboard_views: number | null
          dynamic_views: number | null
          last_seen: string | null
          map_views: number | null
          total_views: number | null
          user_email: string | null
          user_id: string | null
        }
        Relationships: []
      }
      view_usage_daily: {
        Row: {
          day: string | null
          page: string | null
          total_views: number | null
          unique_users: number | null
        }
        Relationships: []
      }
      view_usage_monthly: {
        Row: {
          page: string | null
          total_views: number | null
          unique_users: number | null
          usage_month: string | null
        }
        Relationships: []
      }
      view_wa_daily: {
        Row: {
          completions: number | null
          day: string | null
          errors: number | null
          total_events: number | null
          unique_users: number | null
        }
        Relationships: []
      }
      view_wa_errors: {
        Row: {
          flow: string | null
          from_step: string | null
          id: number | null
          occurred_at: string | null
          to_step: string | null
        }
        Relationships: []
      }
      view_wa_flow_summary: {
        Row: {
          abandoned: number | null
          completed: number | null
          completion_pct: number | null
          errors: number | null
          flow: string | null
          started: number | null
          unique_users: number | null
        }
        Relationships: []
      }
      view_wa_funnel: {
        Row: {
          entries: number | null
          flow: string | null
          step: string | null
          unique_users: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      admin_get_report_config: { Args: never; Returns: Json }
      admin_set_report_dimensions: {
        Args: { p_dimensions: Json; p_report_key: string }
        Returns: undefined
      }
      admin_set_report_measures: {
        Args: { p_measures: Json; p_report_key: string }
        Returns: undefined
      }
      caller_allowed_countries: { Args: never; Returns: string[] }
      check_upload_exists: {
        Args: { p_year: number }
        Returns: {
          inserted_at: string
          uploaded_by: string
        }[]
      }
      count_all_kpi_rows: { Args: { p_year: number }; Returns: number }
      count_ingest_runs: { Args: never; Returns: number }
      count_level_one_upload_log: { Args: never; Returns: number }
      count_milestone_upload_log: { Args: never; Returns: number }
      count_upload_log: { Args: never; Returns: number }
      count_wa_errors: { Args: never; Returns: number }
      create_dashlet: {
        Args: {
          p_chart_type: string
          p_comment: string
          p_comment_enabled: boolean
          p_dashboard_id: number
          p_description: string
          p_display_mode: string
          p_group_id: number
          p_key: string
          p_kpi_disagg1_filters: string[]
          p_kpi_disagg2_filters: string[]
          p_kpi_id: string
          p_kpi_split_mode: string
          p_label: string
          p_metric_config_ids: number[]
          p_parent_key: string
          p_show_milestone?: boolean
          p_updated_by: string
        }
        Returns: {
          chart_type: string | null
          comment: string | null
          comment_enabled: boolean
          created_at: string
          dashboard_id: number
          display_mode: string | null
          group_id: number | null
          id: number
          permission_key: string
          source_type: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "dashlets"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      default_dashboard_id: { Args: { p_source_type: string }; Returns: number }
      district_report_children: {
        Args: { p_district: string; p_year?: number }
        Returns: {
          bursary_boys: number
          bursary_girls: number
          tertiary_girls: number
          total_boys: number
          total_girls: number
        }[]
      }
      district_report_finance: {
        Args: { p_district: string; p_year?: number }
        Returns: {
          grants_boys: number
          grants_count: number
          grants_girls: number
          grants_total: number
          loans_boys: number
          loans_count: number
          loans_girls: number
          loans_total: number
        }[]
      }
      district_report_guides_by_type: {
        Args: { p_district: string }
        Returns: {
          active_count: number
          guide_type: string
        }[]
      }
      district_report_people: {
        Args: { p_district: string }
        Returns: {
          active_guides: number
          cama_members: number
          total_guides: number
        }[]
      }
      district_report_schools: {
        Args: { p_district: string }
        Returns: {
          active_partner_schools: number
          top_schools: string
        }[]
      }
      get_all_kpi_rows: {
        Args: { p_limit?: number; p_offset?: number; p_year: number }
        Returns: {
          countries: Json
          disaggregation1: string
          disaggregation2: string
          indicator: string
          indicator_group: string
          kpi_no: string
          row_id: number
          total: string
          updated_date: string
          value_type: string
        }[]
      }
      get_available_countries: {
        Args: never
        Returns: {
          country: string
        }[]
      }
      get_bot_districts: {
        Args: never
        Returns: {
          country: string
          district: string
          province: string
        }[]
      }
      get_dashboard_data: { Args: never; Returns: Json }
      get_dashboard_data_filtered: {
        Args: {
          p_countries?: string[]
          p_districts?: string[]
          p_metrics?: string[]
          p_provinces?: string[]
          p_school_types?: string[]
          p_schools?: string[]
          p_year_end?: number
          p_year_start?: number
        }
        Returns: Json
      }
      get_dashboard_data_scoped: { Args: never; Returns: Json }
      get_dashboard_metadata: { Args: never; Returns: Json }
      get_dashboards: {
        Args: never
        Returns: {
          display_order: number
          id: number
          is_default: boolean
          key: string
          label: string
          source_type: string
        }[]
      }
      get_dashlet_comments: {
        Args: never
        Returns: {
          comment: string
          permission_key: string
          updated_at: string
        }[]
      }
      get_dashlet_data: {
        Args: {
          p_dashlet_elements: number[]
          p_end_year: number
          p_start_year: number
        }
        Returns: {
          country: string
          dashlet_element: number
          data_element: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          kpi_id: string
          row_scope: string
          toggle: string
          update_quarter: string
          value: string
          year: number
          year_quarter: number
        }[]
      }
      get_dashlet_targets: {
        Args: { p_dashlet_elements: number[]; p_year: number }
        Returns: {
          country: string
          dashlet_element: number
          target_value: number
        }[]
      }
      get_dashlets_for_comment_edit: {
        Args: never
        Returns: {
          comment: string
          comment_enabled: boolean
          group_display_order: number
          group_id: number
          group_name: string
          label: string
          permission_key: string
        }[]
      }
      get_deletion_run_log_entry: {
        Args: { p_run_id: string }
        Returns: {
          deletions_applied: number
          deletions_found: number
          error: string
          finished_at: string
          objects_queried: number
          run_id: string
          started_at: string
          status: string
        }[]
      }
      get_district_kpi_data: {
        Args: never
        Returns: {
          beneficiary_count: number
          country_name: string
          country_slug: string
          district_name: string
          id: string
          kpis: Json
          program_count: number
          risk_score: number
        }[]
      }
      get_duplicate_rows: {
        Args: { p_batch_id: string }
        Returns: {
          disaggregation_level_one: string
          disaggregation_level_two: string
          kpi_group: string
          kpi_id: string
          occurrences: number
          row_ids: string[]
          row_scope: string
          year: number
        }[]
      }
      get_etl_batch_log: {
        Args: never
        Returns: {
          batch_id: string
          error_message: string
          finished_at: string
          source_system: string
          started_at: string
          status: string
        }[]
      }
      get_etl_batch_log_entry: {
        Args: { p_batch_id: string }
        Returns: {
          batch_id: string
          error_message: string
          finished_at: string
          source_system: string
          started_at: string
          status: string
        }[]
      }
      get_ingest_fn_state: {
        Args: { p_run_id: string }
        Returns: {
          attempt_count: number
          cursor: string
          fn_name: string
          rows_fetched: number
          status: string
        }[]
      }
      get_ingest_runs: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          attempt_count: number
          current_wave: number
          error: string
          finished_at: string
          lease_expires_at: string
          run_id: string
          since: string
          started_at: string
          started_by: string
          status: string
        }[]
      }
      get_kpi_coverage_summary: {
        Args: never
        Returns: {
          countries_covered: number
          kpis_with_data: number
          last_updated: string
          total_kpis: number
          years_covered: number
        }[]
      }
      get_kpi_dashlet_data: { Args: { p_kpi_ids: string[] }; Returns: Json }
      get_kpi_dashlet_milestones: {
        Args: { p_kpi_ids: string[] }
        Returns: {
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          source_kpi_id: string
          value: number
          value_type: string
          year: number
        }[]
      }
      get_kpi_dashlets: {
        Args: { p_dashboard_id?: number }
        Returns: {
          chart_type: string
          description: string
          display_mode: string
          group_display_order: number
          group_id: number
          group_name: string
          kpi_disagg1_filters: string[]
          kpi_disagg2_filters: string[]
          kpi_id: string
          kpi_split_mode: string
          label: string
          permission_key: string
          show_milestone: boolean
        }[]
      }
      get_kpi_dashlets_admin: {
        Args: { p_dashboard_id?: number }
        Returns: {
          chart_type: string
          comment: string
          comment_enabled: boolean
          description: string
          display_mode: string
          group_display_order: number
          group_id: number
          group_name: string
          has_pending_draft: boolean
          kpi_disagg1_filters: string[]
          kpi_disagg2_filters: string[]
          kpi_id: string
          kpi_split_mode: string
          label: string
          permission_key: string
          show_milestone: boolean
          status: string
        }[]
      }
      get_kpi_definitions: {
        Args: never
        Returns: {
          definition: string
          indicator: string
          indicator_frequency: string
          indicator_start: string
          kpi_group: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      get_kpi_definitions_summary: { Args: never; Returns: Json }
      get_kpi_disaggregations: {
        Args: { p_kpi_id: string }
        Returns: {
          disaggregation_level_one: string
          disaggregation_level_two: string
        }[]
      }
      get_last_complete_kpi_year: { Args: never; Returns: number }
      get_level_one_upload_log: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          batch_id: string
          error_msg: string
          inserted_at: string
          rows_added: number
          rows_updated: number
          source_file: string
          status: string
          total_rows: number
          uploaded_by: string
        }[]
      }
      get_loaded_years: {
        Args: never
        Returns: {
          inserted_at: string
          rows_duplicate: number
          rows_loaded: number
          source_file: string
          update_quarter: string
          uploaded_by: string
          year: number
        }[]
      }
      get_main_dashboard_dashlets: {
        Args: { p_dashboard_id?: number }
        Returns: {
          category_description: string
          category_display_order: number
          category_display_title: string
          category_id: number
          category_name: string
          chart_type: string
          description: string
          display_mode: string
          group_display_order: number
          group_id: number
          group_name: string
          kpi_disagg1_filters: string[]
          kpi_disagg2_filters: string[]
          kpi_id: string
          kpi_split_mode: string
          label: string
          permission_key: string
          show_milestone: boolean
        }[]
      }
      get_metric_config: {
        Args: never
        Returns: {
          enabled: boolean
          id: number
          metric_name: string
          sort_order: number
        }[]
      }
      get_milestone_upload_log: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          batch_id: string
          error_msg: string
          inserted_at: string
          rows_loaded: number
          source_file: string
          status: string
          uploaded_by: string
        }[]
      }
      get_missing_kpi_definitions: {
        Args: never
        Returns: {
          dashboard_page: string
          data_element: string
          kpi_id: string
        }[]
      }
      get_my_countries: { Args: never; Returns: string[] }
      get_my_permissions: {
        Args: never
        Returns: {
          key: string
        }[]
      }
      get_observed_kpi: {
        Args: { p_kpi_id: string }
        Returns: {
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          kpi_id: string
          row_scope: string
          value: string
          year: number
          year_quarter: number
        }[]
      }
      get_report_catalog: { Args: never; Returns: Json }
      get_report_dimension_values: {
        Args: { p_column: string; p_report_key: string }
        Returns: Json
      }
      get_report_pivot: {
        Args: {
          p_countries?: string[]
          p_districts?: string[]
          p_filters?: Json
          p_group_by?: string[]
          p_measures?: string[]
          p_provinces?: string[]
          p_report_key: string
          p_schools?: string[]
          p_year_end?: number
          p_year_start?: number
        }
        Returns: Json
      }
      get_salesforce_dashlet_data: {
        Args: { p_metric_config_ids: number[] }
        Returns: {
          country: string
          metric_config_id: number
          metric_name: string
          value: number
          year: number
        }[]
      }
      get_salesforce_dashlets: {
        Args: { p_dashboard_id?: number }
        Returns: {
          chart_type: string
          description: string
          group_display_order: number
          group_id: number
          group_name: string
          label: string
          metric_config_ids: number[]
          metric_names: string[]
          permission_key: string
        }[]
      }
      get_salesforce_dashlets_admin: {
        Args: { p_dashboard_id?: number }
        Returns: {
          chart_type: string
          comment: string
          comment_enabled: boolean
          description: string
          group_display_order: number
          group_id: number
          group_name: string
          has_pending_draft: boolean
          label: string
          metric_config_ids: number[]
          metric_names: string[]
          permission_key: string
          status: string
        }[]
      }
      get_school_point_data: {
        Args: never
        Returns: {
          country_name: string
          country_slug: string
          district_name: string
          geo_source: string
          kpis: Json
          latitude: number
          longitude: number
          province: string
          school_id: string
          school_name: string
        }[]
      }
      get_source_view_columns: { Args: { p_report_key: string }; Returns: Json }
      get_upload_log: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          batch_id: string
          error_msg: string
          inserted_at: string
          row_count: number
          rows_duplicate: number
          rows_loaded: number
          rows_unmatched: number
          source_file: string
          status: string
          uploaded_by: string
          year: number
        }[]
      }
      get_usage_by_page: {
        Args: never
        Returns: {
          page: string
          total_views: number
          unique_users: number
        }[]
      }
      get_usage_by_user: {
        Args: never
        Returns: {
          dashboard_views: number
          dynamic_views: number
          last_seen: string
          map_views: number
          total_views: number
          user_email: string
          user_id: string
        }[]
      }
      get_usage_daily: {
        Args: never
        Returns: {
          day: string
          page: string
          total_views: number
          unique_users: number
        }[]
      }
      get_usage_monthly: {
        Args: never
        Returns: {
          page: string
          total_views: number
          unique_users: number
          usage_month: string
        }[]
      }
      get_user_countries: { Args: { p_user_id: string }; Returns: string[] }
      get_view_column_values: {
        Args: { p_column_name: string; p_view_name: string }
        Returns: Json
      }
      get_view_columns: {
        Args: { p_view_name: string }
        Returns: {
          column_name: string
          data_type: string
        }[]
      }
      get_wa_daily: {
        Args: never
        Returns: {
          completions: number
          day: string
          errors: number
          total_events: number
          unique_users: number
        }[]
      }
      get_wa_errors: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          flow: string
          from_step: string
          id: number
          occurred_at: string
          to_step: string
        }[]
      }
      get_wa_flow_summary: {
        Args: never
        Returns: {
          abandoned: number
          completed: number
          completion_pct: number
          errors: number
          flow: string
          started: number
          unique_users: number
        }[]
      }
      get_wa_funnel: {
        Args: { p_flow?: string }
        Returns: {
          entries: number
          flow: string
          step: string
          unique_users: number
        }[]
      }
      get_wa_report_permissions: {
        Args: { p_whatsapp_user_id: number }
        Returns: {
          key: string
        }[]
      }
      get_warehouse_counts: {
        Args: never
        Returns: {
          country: string
          row_count: number
          source_object: string
          year: number
        }[]
      }
      kpi_delete_year: { Args: { p_year: number }; Returns: Json }
      kpi_milestone_groups: {
        Args: never
        Returns: {
          kpi_group: string
        }[]
      }
      kpi_milestone_indicators: {
        Args: { p_kpi_group: string }
        Returns: {
          indicator: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      kpi_milestone_report: {
        Args: { p_indicator: string; p_kpi_group: string; p_year: number }
        Returns: {
          actual_value: number
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          is_visible: boolean
          milestone_value: number
          value_type: string
        }[]
      }
      kpi_milestone_years: {
        Args: never
        Returns: {
          year: number
        }[]
      }
      kpi_report_all_groups: {
        Args: never
        Returns: {
          kpi_group: string
        }[]
      }
      kpi_report_all_indicators: {
        Args: { p_kpi_group: string }
        Returns: {
          indicator: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      kpi_report_country: { Args: { p_district: string }; Returns: string }
      kpi_report_groups: {
        Args: { p_country: string; p_year: number }
        Returns: {
          kpi_group: string
        }[]
      }
      kpi_report_indicator_detail: {
        Args: {
          p_country: string
          p_indicator: string
          p_kpi_group: string
          p_year: number
        }
        Returns: {
          definition: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          source_kpi_id: string
          value: string
          value_type: string
        }[]
      }
      kpi_report_indicator_trend: {
        Args: { p_country: string; p_indicator: string; p_kpi_group: string }
        Returns: {
          disaggregation_level_one: string
          disaggregation_level_two: string
          is_visible: boolean
          value: string
          value_type: string
          year: number
        }[]
      }
      kpi_report_indicator_trend_all_countries: {
        Args: { p_indicator: string; p_kpi_group: string }
        Returns: {
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          is_visible: boolean
          value: string
          value_type: string
          year: number
        }[]
      }
      kpi_report_indicators: {
        Args: { p_country: string; p_kpi_group: string; p_year: number }
        Returns: {
          indicator: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      kpi_report_years: {
        Args: { p_country: string }
        Returns: {
          year: number
        }[]
      }
      list_district_access: {
        Args: {
          p_caller_id: string
          p_district_id?: string
          p_page?: number
          p_page_size?: number
          p_search?: string
          p_sort_dir?: string
          p_sort_key?: string
          p_status?: string
        }
        Returns: Json
      }
      list_portal_users: {
        Args: {
          p_admin_role?: string
          p_caller_id: string
          p_country?: string
          p_page?: number
          p_page_size?: number
          p_role_id?: number
          p_search?: string
          p_sort_dir?: string
          p_sort_key?: string
          p_status?: string
        }
        Returns: Json
      }
      list_whatsapp_users: {
        Args: {
          p_caller_id: string
          p_filter?: string
          p_page?: number
          p_page_size?: number
          p_search?: string
          p_sort_dir?: string
          p_sort_key?: string
        }
        Returns: Json
      }
      log_page_view: { Args: { p_page: string }; Returns: undefined }
      purge_portal_page_views: {
        Args: { p_retention_days?: number }
        Returns: undefined
      }
      refresh_dashboard_data_agg: { Args: never; Returns: undefined }
      rollup_portal_usage_monthly: {
        Args: { p_month: string }
        Returns: undefined
      }
      set_dashlet_comment: {
        Args: {
          p_comment: string
          p_is_enabled: boolean
          p_permission_key: string
        }
        Returns: undefined
      }
      set_dashlet_comment_direct: {
        Args: {
          p_comment: string
          p_is_enabled: boolean
          p_permission_key: string
        }
        Returns: undefined
      }
      set_default_dashboard: {
        Args: { p_dashboard_id: number }
        Returns: undefined
      }
      set_user_countries: {
        Args: { p_countries: string[]; p_user_id: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  rep_raw: {
    Tables: {
      academic_record: {
        Row: {
          academic_record_type: string | null
          accommodation: string | null
          attendance_issues: string | null
          attendance_issues_detail: string | null
          contact_record_type: string | null
          country_name: string | null
          date_dropped_out: string | null
          district_id: string | null
          district_name: string | null
          donor_activity_id: string | null
          donor_code_id: string | null
          end_date: string | null
          form: string | null
          person_id: string | null
          project_code_id: string | null
          received_financial_support: string | null
          record_type_id: string | null
          repeated: string | null
          row_id: number | null
          salesforce_id: string | null
          school_institution_id: string | null
          start_date: string | null
          unique_id: string | null
          year: string | null
        }
        Insert: {
          academic_record_type?: string | null
          accommodation?: string | null
          attendance_issues?: string | null
          attendance_issues_detail?: string | null
          contact_record_type?: string | null
          country_name?: string | null
          date_dropped_out?: string | null
          district_id?: string | null
          district_name?: string | null
          donor_activity_id?: string | null
          donor_code_id?: string | null
          end_date?: string | null
          form?: string | null
          person_id?: string | null
          project_code_id?: string | null
          received_financial_support?: string | null
          record_type_id?: string | null
          repeated?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_institution_id?: string | null
          start_date?: string | null
          unique_id?: string | null
          year?: string | null
        }
        Update: {
          academic_record_type?: string | null
          accommodation?: string | null
          attendance_issues?: string | null
          attendance_issues_detail?: string | null
          contact_record_type?: string | null
          country_name?: string | null
          date_dropped_out?: string | null
          district_id?: string | null
          district_name?: string | null
          donor_activity_id?: string | null
          donor_code_id?: string | null
          end_date?: string | null
          form?: string | null
          person_id?: string | null
          project_code_id?: string | null
          received_financial_support?: string | null
          record_type_id?: string | null
          repeated?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_institution_id?: string | null
          start_date?: string | null
          unique_id?: string | null
          year?: string | null
        }
        Relationships: []
      }
      all_kpis: {
        Row: {
          batch_id: string | null
          countries: Json | null
          disaggregation1: string | null
          disaggregation2: string | null
          indicator: string | null
          indicator_group: string | null
          kpi_no: string | null
          row_id: number | null
          salesforce_id: string | null
          total: string | null
          update_quarter: string | null
          updated_date: string | null
          value_type: string | null
          year_of_kpis: string | null
        }
        Insert: {
          batch_id?: string | null
          countries?: Json | null
          disaggregation1?: string | null
          disaggregation2?: string | null
          indicator?: string | null
          indicator_group?: string | null
          kpi_no?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          total?: string | null
          update_quarter?: string | null
          updated_date?: string | null
          value_type?: string | null
          year_of_kpis?: string | null
        }
        Update: {
          batch_id?: string | null
          countries?: Json | null
          disaggregation1?: string | null
          disaggregation2?: string | null
          indicator?: string | null
          indicator_group?: string | null
          kpi_no?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          total?: string | null
          update_quarter?: string | null
          updated_date?: string | null
          value_type?: string | null
          year_of_kpis?: string | null
        }
        Relationships: []
      }
      cama_members: {
        Row: {
          contact_id: string | null
          country_country_name: string | null
          date_joined_cama: string | null
          districtschool: string | null
          full_name: string | null
          partner_school: string | null
          row_id: number | null
          salesforce_id: string | null
          school_id_code: string | null
          schoolinstitution_school_name: string | null
        }
        Insert: {
          contact_id?: string | null
          country_country_name?: string | null
          date_joined_cama?: string | null
          districtschool?: string | null
          full_name?: string | null
          partner_school?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_id_code?: string | null
          schoolinstitution_school_name?: string | null
        }
        Update: {
          contact_id?: string | null
          country_country_name?: string | null
          date_joined_cama?: string | null
          districtschool?: string | null
          full_name?: string | null
          partner_school?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_id_code?: string | null
          schoolinstitution_school_name?: string | null
        }
        Relationships: []
      }
      contacts: {
        Row: {
          active_on_bursary: string | null
          contact_deceased: string | null
          country_id: string | null
          country_name: string | null
          date_joined_cama: string | null
          district_id: string | null
          donor_activity_id: string | null
          donor_code_id: string | null
          full_name: string | null
          gender: string | null
          lg_social_support_recipient: string | null
          npsp_deceased: string | null
          orphan_status: string | null
          project_code_id: string | null
          record_type_id: string | null
          record_type_name: string | null
          row_id: number | null
          salesforce_id: string | null
          school_id: string | null
          wg_difficulty_overall: string | null
        }
        Insert: {
          active_on_bursary?: string | null
          contact_deceased?: string | null
          country_id?: string | null
          country_name?: string | null
          date_joined_cama?: string | null
          district_id?: string | null
          donor_activity_id?: string | null
          donor_code_id?: string | null
          full_name?: string | null
          gender?: string | null
          lg_social_support_recipient?: string | null
          npsp_deceased?: string | null
          orphan_status?: string | null
          project_code_id?: string | null
          record_type_id?: string | null
          record_type_name?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_id?: string | null
          wg_difficulty_overall?: string | null
        }
        Update: {
          active_on_bursary?: string | null
          contact_deceased?: string | null
          country_id?: string | null
          country_name?: string | null
          date_joined_cama?: string | null
          district_id?: string | null
          donor_activity_id?: string | null
          donor_code_id?: string | null
          full_name?: string | null
          gender?: string | null
          lg_social_support_recipient?: string | null
          npsp_deceased?: string | null
          orphan_status?: string | null
          project_code_id?: string | null
          record_type_id?: string | null
          record_type_name?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_id?: string | null
          wg_difficulty_overall?: string | null
        }
        Relationships: []
      }
      countries: {
        Row: {
          country_name: string | null
          row_id: number | null
          salesforce_id: string | null
          unique_id: string | null
        }
        Insert: {
          country_name?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          unique_id?: string | null
        }
        Update: {
          country_name?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          unique_id?: string | null
        }
        Relationships: []
      }
      dimension_1_roc: {
        Row: {
          active: string | null
          available_country: string | null
          description: string | null
          name: string | null
          reporting_code: string | null
          row_id: number | null
          salesforce_id: string | null
        }
        Insert: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
        }
        Update: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
        }
        Relationships: []
      }
      dimension_2_roc: {
        Row: {
          active: string | null
          available_country: string | null
          description: string | null
          name: string | null
          reporting_code: string | null
          row_id: number | null
          salesforce_id: string | null
        }
        Insert: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
        }
        Update: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
        }
        Relationships: []
      }
      dimension_3_roc: {
        Row: {
          active: string | null
          available_country: string | null
          description: string | null
          end_date: string | null
          name: string | null
          reporting_code: string | null
          row_id: number | null
          salesforce_id: string | null
          start_date: string | null
        }
        Insert: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          end_date?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          start_date?: string | null
        }
        Update: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          end_date?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          start_date?: string | null
        }
        Relationships: []
      }
      dimension_4_roc: {
        Row: {
          active: string | null
          available_country: string | null
          description: string | null
          dimension_3_id: string | null
          name: string | null
          reporting_code: string | null
          row_id: number | null
          salesforce_id: string | null
        }
        Insert: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          dimension_3_id?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
        }
        Update: {
          active?: string | null
          available_country?: string | null
          description?: string | null
          dimension_3_id?: string | null
          name?: string | null
          reporting_code?: string | null
          row_id?: number | null
          salesforce_id?: string | null
        }
        Relationships: []
      }
      districts: {
        Row: {
          active_partner_district: string | null
          active_schools: string | null
          country_id: string | null
          country_name: string | null
          date_camfed_began_work: string | null
          district_name: string | null
          inactive_schools: string | null
          partner_schools: string | null
          primary_partner_schools: string | null
          province: string | null
          region_id: string | null
          row_id: number | null
          salesforce_id: string | null
          secondary_partner_schools: string | null
          terrain: string | null
          total_schools: string | null
          unique_id: string | null
        }
        Insert: {
          active_partner_district?: string | null
          active_schools?: string | null
          country_id?: string | null
          country_name?: string | null
          date_camfed_began_work?: string | null
          district_name?: string | null
          inactive_schools?: string | null
          partner_schools?: string | null
          primary_partner_schools?: string | null
          province?: string | null
          region_id?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          secondary_partner_schools?: string | null
          terrain?: string | null
          total_schools?: string | null
          unique_id?: string | null
        }
        Update: {
          active_partner_district?: string | null
          active_schools?: string | null
          country_id?: string | null
          country_name?: string | null
          date_camfed_began_work?: string | null
          district_name?: string | null
          inactive_schools?: string | null
          partner_schools?: string | null
          primary_partner_schools?: string | null
          province?: string | null
          region_id?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          secondary_partner_schools?: string | null
          terrain?: string | null
          total_schools?: string | null
          unique_id?: string | null
        }
        Relationships: []
      }
      duplicate_rows: {
        Row: {
          batch_id: string
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number
          inserted_at: string
          kpi_group: string | null
          kpi_id: string
          occurrences: number
          row_ids: string[] | null
          row_scope: string | null
          year: number | null
        }
        Insert: {
          batch_id: string
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          id?: number
          inserted_at?: string
          kpi_group?: string | null
          kpi_id: string
          occurrences?: number
          row_ids?: string[] | null
          row_scope?: string | null
          year?: number | null
        }
        Update: {
          batch_id?: string
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          id?: number
          inserted_at?: string
          kpi_group?: string | null
          kpi_id?: string
          occurrences?: number
          row_ids?: string[] | null
          row_scope?: string | null
          year?: number | null
        }
        Relationships: []
      }
      grant_recipients: {
        Row: {
          amount_given: string | null
          contact_record_type: string | null
          country: string | null
          district_id: string | null
          donor_id: string | null
          grant_date: string | null
          grant_name: string | null
          person_id: string | null
          record_type_id: string | null
          row_id: number | null
          salesforce_id: string | null
          status: string | null
          unique_id: string | null
        }
        Insert: {
          amount_given?: string | null
          contact_record_type?: string | null
          country?: string | null
          district_id?: string | null
          donor_id?: string | null
          grant_date?: string | null
          grant_name?: string | null
          person_id?: string | null
          record_type_id?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          status?: string | null
          unique_id?: string | null
        }
        Update: {
          amount_given?: string | null
          contact_record_type?: string | null
          country?: string | null
          district_id?: string | null
          donor_id?: string | null
          grant_date?: string | null
          grant_name?: string | null
          person_id?: string | null
          record_type_id?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          status?: string | null
          unique_id?: string | null
        }
        Relationships: []
      }
      guides: {
        Row: {
          contact_deceased: string | null
          contact_id: string | null
          contact_npsp_deceased: string | null
          contact_record_type: string | null
          date_completed_guide_programme: string | null
          date_joined_guide_programme: string | null
          district_id: string | null
          donor_id: string | null
          guide_dropout_reason: string | null
          guide_name: string | null
          guide_specialty: string | null
          guide_status: string | null
          guide_type: string | null
          row_id: number | null
          salesforce_id: string | null
          school_id: string | null
          trained_in_climate_education: string | null
        }
        Insert: {
          contact_deceased?: string | null
          contact_id?: string | null
          contact_npsp_deceased?: string | null
          contact_record_type?: string | null
          date_completed_guide_programme?: string | null
          date_joined_guide_programme?: string | null
          district_id?: string | null
          donor_id?: string | null
          guide_dropout_reason?: string | null
          guide_name?: string | null
          guide_specialty?: string | null
          guide_status?: string | null
          guide_type?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_id?: string | null
          trained_in_climate_education?: string | null
        }
        Update: {
          contact_deceased?: string | null
          contact_id?: string | null
          contact_npsp_deceased?: string | null
          contact_record_type?: string | null
          date_completed_guide_programme?: string | null
          date_joined_guide_programme?: string | null
          district_id?: string | null
          donor_id?: string | null
          guide_dropout_reason?: string | null
          guide_name?: string | null
          guide_specialty?: string | null
          guide_status?: string | null
          guide_type?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_id?: string | null
          trained_in_climate_education?: string | null
        }
        Relationships: []
      }
      level_one_kpis: {
        Row: {
          annual_newly_supported: string | null
          batch_id: string | null
          country: string | null
          disaggregation_gender: string | null
          gender: string | null
          kpi: string | null
          row_id: number | null
          salesforce_id: string | null
          school_level: string | null
          type: string | null
          value: string | null
          year: string | null
        }
        Insert: {
          annual_newly_supported?: string | null
          batch_id?: string | null
          country?: string | null
          disaggregation_gender?: string | null
          gender?: string | null
          kpi?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_level?: string | null
          type?: string | null
          value?: string | null
          year?: string | null
        }
        Update: {
          annual_newly_supported?: string | null
          batch_id?: string | null
          country?: string | null
          disaggregation_gender?: string | null
          gender?: string | null
          kpi?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_level?: string | null
          type?: string | null
          value?: string | null
          year?: string | null
        }
        Relationships: []
      }
      level_one_upload_log: {
        Row: {
          batch_id: string
          error_msg: string | null
          id: number
          inserted_at: string
          rows_added: number
          rows_updated: number
          source_file: string | null
          status: string
          total_rows: number
          uploaded_by: string | null
        }
        Insert: {
          batch_id: string
          error_msg?: string | null
          id?: number
          inserted_at?: string
          rows_added?: number
          rows_updated?: number
          source_file?: string | null
          status: string
          total_rows?: number
          uploaded_by?: string | null
        }
        Update: {
          batch_id?: string
          error_msg?: string | null
          id?: number
          inserted_at?: string
          rows_added?: number
          rows_updated?: number
          source_file?: string | null
          status?: string
          total_rows?: number
          uploaded_by?: string | null
        }
        Relationships: []
      }
      loan_recipients: {
        Row: {
          active: string | null
          client_id: string | null
          completed: string | null
          contact_record_id: string | null
          contact_record_type: string | null
          country: string | null
          currency_iso_code: string | null
          default_date: string | null
          default_loan: string | null
          delinquent: string | null
          disbursal_date: string | null
          district: string | null
          donor_code_id: string | null
          group_loan: string | null
          historical: string | null
          kiva_client_id: string | null
          loan_name: string | null
          loan_status: string | null
          loan_type_id: string | null
          loan_value: string | null
          record_type_id: string | null
          repayment_status: string | null
          repayment_term: string | null
          row_id: number | null
          salesforce_id: string | null
          status: string | null
          written_off: string | null
        }
        Insert: {
          active?: string | null
          client_id?: string | null
          completed?: string | null
          contact_record_id?: string | null
          contact_record_type?: string | null
          country?: string | null
          currency_iso_code?: string | null
          default_date?: string | null
          default_loan?: string | null
          delinquent?: string | null
          disbursal_date?: string | null
          district?: string | null
          donor_code_id?: string | null
          group_loan?: string | null
          historical?: string | null
          kiva_client_id?: string | null
          loan_name?: string | null
          loan_status?: string | null
          loan_type_id?: string | null
          loan_value?: string | null
          record_type_id?: string | null
          repayment_status?: string | null
          repayment_term?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          status?: string | null
          written_off?: string | null
        }
        Update: {
          active?: string | null
          client_id?: string | null
          completed?: string | null
          contact_record_id?: string | null
          contact_record_type?: string | null
          country?: string | null
          currency_iso_code?: string | null
          default_date?: string | null
          default_loan?: string | null
          delinquent?: string | null
          disbursal_date?: string | null
          district?: string | null
          donor_code_id?: string | null
          group_loan?: string | null
          historical?: string | null
          kiva_client_id?: string | null
          loan_name?: string | null
          loan_status?: string | null
          loan_type_id?: string | null
          loan_value?: string | null
          record_type_id?: string | null
          repayment_status?: string | null
          repayment_term?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          status?: string | null
          written_off?: string | null
        }
        Relationships: []
      }
      milestone_upload_log: {
        Row: {
          batch_id: string
          error_msg: string | null
          id: number
          inserted_at: string
          rows_loaded: number | null
          source_file: string | null
          status: string | null
          uploaded_by: string | null
        }
        Insert: {
          batch_id: string
          error_msg?: string | null
          id?: number
          inserted_at?: string
          rows_loaded?: number | null
          source_file?: string | null
          status?: string | null
          uploaded_by?: string | null
        }
        Update: {
          batch_id?: string
          error_msg?: string | null
          id?: number
          inserted_at?: string
          rows_loaded?: number | null
          source_file?: string | null
          status?: string | null
          uploaded_by?: string | null
        }
        Relationships: []
      }
      milestones: {
        Row: {
          batch_id: string
          country: string | null
          disaggregation1: string | null
          disaggregation2: string | null
          id: number
          indicator: string | null
          kpi_no: string | null
          row_id: number | null
          value: string | null
          value_type: string | null
          year: string | null
        }
        Insert: {
          batch_id: string
          country?: string | null
          disaggregation1?: string | null
          disaggregation2?: string | null
          id?: number
          indicator?: string | null
          kpi_no?: string | null
          row_id?: number | null
          value?: string | null
          value_type?: string | null
          year?: string | null
        }
        Update: {
          batch_id?: string
          country?: string | null
          disaggregation1?: string | null
          disaggregation2?: string | null
          id?: number
          indicator?: string | null
          kpi_no?: string | null
          row_id?: number | null
          value?: string | null
          value_type?: string | null
          year?: string | null
        }
        Relationships: []
      }
      schools: {
        Row: {
          accommodation_type: string | null
          active_partner_school: string | null
          affiliated_school: string | null
          bursary_clients_current_year: string | null
          cama_supported_cohort: string | null
          country: string | null
          country_number: string | null
          cpp_committee_present: string | null
          cpp_in_place: string | null
          cpp_posted: string | null
          date_camfed_began_support: string | null
          district_code: string | null
          district_id: string | null
          district_name: string | null
          donor_2_id: string | null
          donor_3_id: string | null
          donor_id: string | null
          ever_been_partner_school: string | null
          gea_school: string | null
          grades_covered: string | null
          latest_mv_date: string | null
          latest_tm_update: string | null
          latitude: string | null
          longitude: string | null
          merp: string | null
          monitoring_school: string | null
          number_of_active_lgs: string | null
          province: string | null
          pupil_council_present: string | null
          record_type_id: string | null
          research_participation: string | null
          resources_received: string | null
          row_id: number | null
          salesforce_id: string | null
          school_active_on_bursary: string | null
          school_donor: string | null
          school_name: string | null
          school_type: string | null
          secondary_school_type: string | null
          snf_only_school: string | null
          twc: string | null
          unique_id: string | null
          year_lg_programme_started: string | null
        }
        Insert: {
          accommodation_type?: string | null
          active_partner_school?: string | null
          affiliated_school?: string | null
          bursary_clients_current_year?: string | null
          cama_supported_cohort?: string | null
          country?: string | null
          country_number?: string | null
          cpp_committee_present?: string | null
          cpp_in_place?: string | null
          cpp_posted?: string | null
          date_camfed_began_support?: string | null
          district_code?: string | null
          district_id?: string | null
          district_name?: string | null
          donor_2_id?: string | null
          donor_3_id?: string | null
          donor_id?: string | null
          ever_been_partner_school?: string | null
          gea_school?: string | null
          grades_covered?: string | null
          latest_mv_date?: string | null
          latest_tm_update?: string | null
          latitude?: string | null
          longitude?: string | null
          merp?: string | null
          monitoring_school?: string | null
          number_of_active_lgs?: string | null
          province?: string | null
          pupil_council_present?: string | null
          record_type_id?: string | null
          research_participation?: string | null
          resources_received?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_active_on_bursary?: string | null
          school_donor?: string | null
          school_name?: string | null
          school_type?: string | null
          secondary_school_type?: string | null
          snf_only_school?: string | null
          twc?: string | null
          unique_id?: string | null
          year_lg_programme_started?: string | null
        }
        Update: {
          accommodation_type?: string | null
          active_partner_school?: string | null
          affiliated_school?: string | null
          bursary_clients_current_year?: string | null
          cama_supported_cohort?: string | null
          country?: string | null
          country_number?: string | null
          cpp_committee_present?: string | null
          cpp_in_place?: string | null
          cpp_posted?: string | null
          date_camfed_began_support?: string | null
          district_code?: string | null
          district_id?: string | null
          district_name?: string | null
          donor_2_id?: string | null
          donor_3_id?: string | null
          donor_id?: string | null
          ever_been_partner_school?: string | null
          gea_school?: string | null
          grades_covered?: string | null
          latest_mv_date?: string | null
          latest_tm_update?: string | null
          latitude?: string | null
          longitude?: string | null
          merp?: string | null
          monitoring_school?: string | null
          number_of_active_lgs?: string | null
          province?: string | null
          pupil_council_present?: string | null
          record_type_id?: string | null
          research_participation?: string | null
          resources_received?: string | null
          row_id?: number | null
          salesforce_id?: string | null
          school_active_on_bursary?: string | null
          school_donor?: string | null
          school_name?: string | null
          school_type?: string | null
          secondary_school_type?: string | null
          snf_only_school?: string | null
          twc?: string | null
          unique_id?: string | null
          year_lg_programme_started?: string | null
        }
        Relationships: []
      }
      unmatched_rows: {
        Row: {
          batch_id: string
          id: number
          inserted_at: string
          kpi_id: string
          row_count: number
          sample_country: string | null
          sample_indicator: string | null
          sample_year: number | null
        }
        Insert: {
          batch_id: string
          id?: number
          inserted_at?: string
          kpi_id: string
          row_count?: number
          sample_country?: string | null
          sample_indicator?: string | null
          sample_year?: number | null
        }
        Update: {
          batch_id?: string
          id?: number
          inserted_at?: string
          kpi_id?: string
          row_count?: number
          sample_country?: string | null
          sample_indicator?: string | null
          sample_year?: number | null
        }
        Relationships: []
      }
      upload_log: {
        Row: {
          batch_id: string
          error_msg: string | null
          id: number
          inserted_at: string
          row_count: number
          rows_duplicate: number
          rows_loaded: number
          rows_unmatched: number
          source_file: string | null
          status: string
          update_quarter: string | null
          uploaded_by: string | null
          year: number
        }
        Insert: {
          batch_id: string
          error_msg?: string | null
          id?: number
          inserted_at?: string
          row_count?: number
          rows_duplicate?: number
          rows_loaded?: number
          rows_unmatched?: number
          source_file?: string | null
          status: string
          update_quarter?: string | null
          uploaded_by?: string | null
          year: number
        }
        Update: {
          batch_id?: string
          error_msg?: string | null
          id?: number
          inserted_at?: string
          row_count?: number
          rows_duplicate?: number
          rows_loaded?: number
          rows_unmatched?: number
          source_file?: string | null
          status?: string
          update_quarter?: string | null
          uploaded_by?: string | null
          year?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      truncate_table: { Args: { p_table: string }; Returns: undefined }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  rep_warehouse: {
    Tables: {
      deleted_source_ids: {
        Row: {
          deletion_run_id: string | null
          detected_at: string
          object_name: string
          processed_at: string | null
          salesforce_id: string
          sf_deleted_at: string | null
        }
        Insert: {
          deletion_run_id?: string | null
          detected_at?: string
          object_name: string
          processed_at?: string | null
          salesforce_id: string
          sf_deleted_at?: string | null
        }
        Update: {
          deletion_run_id?: string | null
          detected_at?: string
          object_name?: string
          processed_at?: string | null
          salesforce_id?: string
          sf_deleted_at?: string | null
        }
        Relationships: []
      }
      deletion_run_log: {
        Row: {
          deletions_applied: number | null
          deletions_found: number | null
          error: string | null
          finished_at: string | null
          objects_queried: number | null
          run_id: string
          started_at: string
          status: string
          triggered_by: string | null
        }
        Insert: {
          deletions_applied?: number | null
          deletions_found?: number | null
          error?: string | null
          finished_at?: string | null
          objects_queried?: number | null
          run_id?: string
          started_at?: string
          status?: string
          triggered_by?: string | null
        }
        Update: {
          deletions_applied?: number | null
          deletions_found?: number | null
          error?: string | null
          finished_at?: string | null
          objects_queried?: number | null
          run_id?: string
          started_at?: string
          status?: string
          triggered_by?: string | null
        }
        Relationships: []
      }
      dim_contact: {
        Row: {
          active_on_bursary: boolean | null
          birth_date: string | null
          country: string | null
          district_of_origin: string | null
          district_of_residence: string | null
          gender: string | null
          id: number
          lg_social_support_recipient: boolean | null
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          orphan_status: string | null
          roc_donor_activity_id: number | null
          roc_donor_id: number | null
          roc_project_code_id: number | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          source_contact_id: string
          wg_difficulty_overall: string | null
        }
        Insert: {
          active_on_bursary?: boolean | null
          birth_date?: string | null
          country?: string | null
          district_of_origin?: string | null
          district_of_residence?: string | null
          gender?: string | null
          id?: number
          lg_social_support_recipient?: boolean | null
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          orphan_status?: string | null
          roc_donor_activity_id?: number | null
          roc_donor_id?: number | null
          roc_project_code_id?: number | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_contact_id: string
          wg_difficulty_overall?: string | null
        }
        Update: {
          active_on_bursary?: boolean | null
          birth_date?: string | null
          country?: string | null
          district_of_origin?: string | null
          district_of_residence?: string | null
          gender?: string | null
          id?: number
          lg_social_support_recipient?: boolean | null
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          orphan_status?: string | null
          roc_donor_activity_id?: number | null
          roc_donor_id?: number | null
          roc_project_code_id?: number | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_contact_id?: string
          wg_difficulty_overall?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "dim_contact_roc_donor_activity_id_fkey"
            columns: ["roc_donor_activity_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor_activity"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dim_contact_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dim_contact_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
          {
            foreignKeyName: "dim_contact_roc_project_code_id_fkey"
            columns: ["roc_project_code_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_project_code"
            referencedColumns: ["id"]
          },
        ]
      }
      dim_date: {
        Row: {
          date_value: string
          day: number
          day_name: string
          day_of_week: number
          id: number
          is_weekend: boolean
          month: number
          month_name: string
          quarter: number
          week_of_year: number
          year: number
        }
        Insert: {
          date_value: string
          day: number
          day_name: string
          day_of_week: number
          id: number
          is_weekend: boolean
          month: number
          month_name: string
          quarter: number
          week_of_year: number
          year: number
        }
        Update: {
          date_value?: string
          day?: number
          day_name?: string
          day_of_week?: number
          id?: number
          is_weekend?: boolean
          month?: number
          month_name?: string
          quarter?: number
          week_of_year?: number
          year?: number
        }
        Relationships: []
      }
      dim_geography: {
        Row: {
          active_partner_district: boolean | null
          country: string
          district: string | null
          id: number
          is_country: boolean
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          province: string | null
          roc_geography_id: number | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
        }
        Insert: {
          active_partner_district?: boolean | null
          country: string
          district?: string | null
          id?: number
          is_country?: boolean
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          province?: string | null
          roc_geography_id?: number | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
        }
        Update: {
          active_partner_district?: boolean | null
          country?: string
          district?: string | null
          id?: number
          is_country?: boolean
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          province?: string | null
          roc_geography_id?: number | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
        }
        Relationships: [
          {
            foreignKeyName: "dim_geography_roc_geography_id_fkey"
            columns: ["roc_geography_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_geography"
            referencedColumns: ["id"]
          },
        ]
      }
      dim_kpi: {
        Row: {
          definition: string | null
          id: number
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          short_label: string | null
          source_kpi_id: string | null
        }
        Insert: {
          definition?: string | null
          id?: number
          indicator?: string | null
          indicator_frequency?: string | null
          indicator_start?: string | null
          kpi_group?: string | null
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          short_label?: string | null
          source_kpi_id?: string | null
        }
        Update: {
          definition?: string | null
          id?: number
          indicator?: string | null
          indicator_frequency?: string | null
          indicator_start?: string | null
          kpi_group?: string | null
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          short_label?: string | null
          source_kpi_id?: string | null
        }
        Relationships: []
      }
      dim_roc_donor: {
        Row: {
          active: boolean | null
          available_country: string | null
          end_date: string | null
          id: number
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          name: string | null
          reporting_code: string | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          source_roc_id: string
          start_date: string | null
        }
        Insert: {
          active?: boolean | null
          available_country?: string | null
          end_date?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id: string
          start_date?: string | null
        }
        Update: {
          active?: boolean | null
          available_country?: string | null
          end_date?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id?: string
          start_date?: string | null
        }
        Relationships: []
      }
      dim_roc_donor_activity: {
        Row: {
          active: boolean | null
          available_country: string | null
          donor_id: number | null
          id: number
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          name: string | null
          reporting_code: string | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          source_roc_id: string
        }
        Insert: {
          active?: boolean | null
          available_country?: string | null
          donor_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id: string
        }
        Update: {
          active?: boolean | null
          available_country?: string | null
          donor_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "dim_roc_donor_activity_donor_id_fkey"
            columns: ["donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dim_roc_donor_activity_donor_id_fkey"
            columns: ["donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
        ]
      }
      dim_roc_geography: {
        Row: {
          active: boolean | null
          available_country: string | null
          id: number
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          name: string | null
          reporting_code: string | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          source_roc_id: string
        }
        Insert: {
          active?: boolean | null
          available_country?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id: string
        }
        Update: {
          active?: boolean | null
          available_country?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id?: string
        }
        Relationships: []
      }
      dim_roc_project_code: {
        Row: {
          active: boolean | null
          available_country: string | null
          id: number
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          name: string | null
          reporting_code: string | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          source_roc_id: string
        }
        Insert: {
          active?: boolean | null
          available_country?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id: string
        }
        Update: {
          active?: boolean | null
          available_country?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          name?: string | null
          reporting_code?: string | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          source_roc_id?: string
        }
        Relationships: []
      }
      dim_school: {
        Row: {
          accommodation_type: string | null
          active_on_bursary: boolean | null
          active_partner_school: boolean | null
          affiliated_school: boolean | null
          country: string | null
          cpp_in_place: boolean | null
          date_camfed_began_support: string | null
          district: string | null
          gea_school: boolean | null
          geography_id: number | null
          id: number
          latitude: number | null
          lin_business_hash: string | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          longitude: number | null
          merp: boolean | null
          monitoring_school: boolean | null
          province: string | null
          roc_donor_id: number | null
          scd_effective_from: string | null
          scd_effective_to: string | null
          scd_is_current: boolean
          scd_version: number
          school_name: string | null
          school_type: string | null
          snf_only: boolean | null
          source_school_id: string
        }
        Insert: {
          accommodation_type?: string | null
          active_on_bursary?: boolean | null
          active_partner_school?: boolean | null
          affiliated_school?: boolean | null
          country?: string | null
          cpp_in_place?: boolean | null
          date_camfed_began_support?: string | null
          district?: string | null
          gea_school?: boolean | null
          geography_id?: number | null
          id?: number
          latitude?: number | null
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          longitude?: number | null
          merp?: boolean | null
          monitoring_school?: boolean | null
          province?: string | null
          roc_donor_id?: number | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          school_name?: string | null
          school_type?: string | null
          snf_only?: boolean | null
          source_school_id: string
        }
        Update: {
          accommodation_type?: string | null
          active_on_bursary?: boolean | null
          active_partner_school?: boolean | null
          affiliated_school?: boolean | null
          country?: string | null
          cpp_in_place?: boolean | null
          date_camfed_began_support?: string | null
          district?: string | null
          gea_school?: boolean | null
          geography_id?: number | null
          id?: number
          latitude?: number | null
          lin_business_hash?: string | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          longitude?: number | null
          merp?: boolean | null
          monitoring_school?: boolean | null
          province?: string | null
          roc_donor_id?: number | null
          scd_effective_from?: string | null
          scd_effective_to?: string | null
          scd_is_current?: boolean
          scd_version?: number
          school_name?: string | null
          school_type?: string | null
          snf_only?: boolean | null
          source_school_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "dim_school_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dim_school_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dim_school_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
        ]
      }
      etl_batch_log: {
        Row: {
          batch_id: string
          error_message: string | null
          finished_at: string | null
          rows_closed: number | null
          rows_inserted: number | null
          source_system: string | null
          started_at: string
          status: string
        }
        Insert: {
          batch_id: string
          error_message?: string | null
          finished_at?: string | null
          rows_closed?: number | null
          rows_inserted?: number | null
          source_system?: string | null
          started_at?: string
          status?: string
        }
        Update: {
          batch_id?: string
          error_message?: string | null
          finished_at?: string | null
          rows_closed?: number | null
          rows_inserted?: number | null
          source_system?: string | null
          started_at?: string
          status?: string
        }
        Relationships: []
      }
      fact_cama_membership: {
        Row: {
          contact_id: number | null
          date_joined_cama: string | null
          date_joined_id: number | null
          geography_id: number | null
          id: number
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          partner_school: boolean | null
          school_id: number | null
          source_contact_id: string | null
          source_school_id: string | null
        }
        Insert: {
          contact_id?: number | null
          date_joined_cama?: string | null
          date_joined_id?: number | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          partner_school?: boolean | null
          school_id?: number | null
          source_contact_id?: string | null
          source_school_id?: string | null
        }
        Update: {
          contact_id?: number | null
          date_joined_cama?: string | null
          date_joined_id?: number | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          partner_school?: boolean | null
          school_id?: number | null
          source_contact_id?: string | null
          source_school_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_cama_membership_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "dim_contact"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_cama_membership_date_joined_id_fkey"
            columns: ["date_joined_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_cama_membership_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_cama_membership_school_id_fkey"
            columns: ["school_id"]
            isOneToOne: false
            referencedRelation: "dim_school"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_cama_membership_school_id_fkey"
            columns: ["school_id"]
            isOneToOne: false
            referencedRelation: "view_school_map"
            referencedColumns: ["id"]
          },
        ]
      }
      fact_children_supported: {
        Row: {
          attendance_issues: boolean | null
          contact_id: number | null
          contact_record_type: string | null
          form: string | null
          geography_id: number | null
          id: number
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          received_financial_support: boolean | null
          repeated: boolean | null
          roc_donor_id: number | null
          roc_project_code_id: number | null
          school_id: number | null
          source_academic_record_id: string | null
          source_contact_id: string | null
          source_school_id: string | null
          year: number | null
          year_date_id: number | null
        }
        Insert: {
          attendance_issues?: boolean | null
          contact_id?: number | null
          contact_record_type?: string | null
          form?: string | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          received_financial_support?: boolean | null
          repeated?: boolean | null
          roc_donor_id?: number | null
          roc_project_code_id?: number | null
          school_id?: number | null
          source_academic_record_id?: string | null
          source_contact_id?: string | null
          source_school_id?: string | null
          year?: number | null
          year_date_id?: number | null
        }
        Update: {
          attendance_issues?: boolean | null
          contact_id?: number | null
          contact_record_type?: string | null
          form?: string | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          received_financial_support?: boolean | null
          repeated?: boolean | null
          roc_donor_id?: number | null
          roc_project_code_id?: number | null
          school_id?: number | null
          source_academic_record_id?: string | null
          source_contact_id?: string | null
          source_school_id?: string | null
          year?: number | null
          year_date_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_children_supported_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "dim_contact"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_children_supported_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_children_supported_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_children_supported_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
          {
            foreignKeyName: "fact_children_supported_roc_project_code_id_fkey"
            columns: ["roc_project_code_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_project_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_children_supported_school_id_fkey"
            columns: ["school_id"]
            isOneToOne: false
            referencedRelation: "dim_school"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_children_supported_school_id_fkey"
            columns: ["school_id"]
            isOneToOne: false
            referencedRelation: "view_school_map"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_children_supported_year_date_id_fkey"
            columns: ["year_date_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
        ]
      }
      fact_grants: {
        Row: {
          amount_given: number | null
          contact_id: number | null
          geography_id: number | null
          grant_date: string | null
          grant_date_id: number | null
          grant_status: string | null
          grant_type: string | null
          id: number
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          roc_donor_id: number | null
          source_contact_id: string | null
          source_grant_id: string | null
        }
        Insert: {
          amount_given?: number | null
          contact_id?: number | null
          geography_id?: number | null
          grant_date?: string | null
          grant_date_id?: number | null
          grant_status?: string | null
          grant_type?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          roc_donor_id?: number | null
          source_contact_id?: string | null
          source_grant_id?: string | null
        }
        Update: {
          amount_given?: number | null
          contact_id?: number | null
          geography_id?: number | null
          grant_date?: string | null
          grant_date_id?: number | null
          grant_status?: string | null
          grant_type?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          roc_donor_id?: number | null
          source_contact_id?: string | null
          source_grant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_grants_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "dim_contact"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_grants_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_grants_grant_date_id_fkey"
            columns: ["grant_date_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_grants_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_grants_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
        ]
      }
      fact_guide_assignment: {
        Row: {
          contact_id: number | null
          date_joined_guide_programme: string | null
          date_joined_id: number | null
          date_left_guide_programme: string | null
          date_left_id: number | null
          geography_id: number | null
          guide_dropout_reason: string | null
          guide_specialty: string | null
          guide_status: string | null
          guide_type: string | null
          id: number
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          roc_donor_id: number | null
          school_id: number | null
          source_contact_id: string | null
          source_guide_id: string | null
          source_school_id: string | null
          trained_in_climate_education: boolean | null
        }
        Insert: {
          contact_id?: number | null
          date_joined_guide_programme?: string | null
          date_joined_id?: number | null
          date_left_guide_programme?: string | null
          date_left_id?: number | null
          geography_id?: number | null
          guide_dropout_reason?: string | null
          guide_specialty?: string | null
          guide_status?: string | null
          guide_type?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          roc_donor_id?: number | null
          school_id?: number | null
          source_contact_id?: string | null
          source_guide_id?: string | null
          source_school_id?: string | null
          trained_in_climate_education?: boolean | null
        }
        Update: {
          contact_id?: number | null
          date_joined_guide_programme?: string | null
          date_joined_id?: number | null
          date_left_guide_programme?: string | null
          date_left_id?: number | null
          geography_id?: number | null
          guide_dropout_reason?: string | null
          guide_specialty?: string | null
          guide_status?: string | null
          guide_type?: string | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          roc_donor_id?: number | null
          school_id?: number | null
          source_contact_id?: string | null
          source_guide_id?: string | null
          source_school_id?: string | null
          trained_in_climate_education?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_guide_assignment_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "dim_contact"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_date_joined_id_fkey"
            columns: ["date_joined_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_date_left_id_fkey"
            columns: ["date_left_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_school_id_fkey"
            columns: ["school_id"]
            isOneToOne: false
            referencedRelation: "dim_school"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_guide_assignment_school_id_fkey"
            columns: ["school_id"]
            isOneToOne: false
            referencedRelation: "view_school_map"
            referencedColumns: ["id"]
          },
        ]
      }
      fact_kpi_milestone: {
        Row: {
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          geography_id: number | null
          id: number
          kpi_id: number | null
          lin_inserted_at: string
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          value: number | null
          value_type: string | null
          year: number | null
        }
        Insert: {
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          geography_id?: number | null
          id?: number
          kpi_id?: number | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          value?: number | null
          value_type?: string | null
          year?: number | null
        }
        Update: {
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          geography_id?: number | null
          id?: number
          kpi_id?: number | null
          lin_inserted_at?: string
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          value?: number | null
          value_type?: string | null
          year?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_kpi_milestone_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_kpi_milestone_kpi_id_fkey"
            columns: ["kpi_id"]
            isOneToOne: false
            referencedRelation: "dim_kpi"
            referencedColumns: ["id"]
          },
        ]
      }
      fact_level_one_kpis: {
        Row: {
          annual_newly_supported: string | null
          disaggregation_gender: string | null
          fund_type: string | null
          gender: string | null
          geography_id: number | null
          id: number
          kpi_id: number | null
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          school_level: string | null
          value: number | null
          year: number | null
          year_date_id: number | null
        }
        Insert: {
          annual_newly_supported?: string | null
          disaggregation_gender?: string | null
          fund_type?: string | null
          gender?: string | null
          geography_id?: number | null
          id?: number
          kpi_id?: number | null
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          school_level?: string | null
          value?: number | null
          year?: number | null
          year_date_id?: number | null
        }
        Update: {
          annual_newly_supported?: string | null
          disaggregation_gender?: string | null
          fund_type?: string | null
          gender?: string | null
          geography_id?: number | null
          id?: number
          kpi_id?: number | null
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          school_level?: string | null
          value?: number | null
          year?: number | null
          year_date_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_level_one_kpis_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_level_one_kpis_kpi_id_fkey"
            columns: ["kpi_id"]
            isOneToOne: false
            referencedRelation: "dim_kpi"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_level_one_kpis_year_date_id_fkey"
            columns: ["year_date_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
        ]
      }
      fact_loans: {
        Row: {
          contact_id: number | null
          contact_record_id: string | null
          currency_iso_code: string | null
          disbursal_date: string | null
          disbursal_date_id: number | null
          geography_id: number | null
          id: number
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          loan_status: string | null
          loan_type: string | null
          loan_value: number | null
          roc_donor_id: number | null
          source_contact_id: string | null
          source_loan_id: string | null
          status: string | null
        }
        Insert: {
          contact_id?: number | null
          contact_record_id?: string | null
          currency_iso_code?: string | null
          disbursal_date?: string | null
          disbursal_date_id?: number | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          loan_status?: string | null
          loan_type?: string | null
          loan_value?: number | null
          roc_donor_id?: number | null
          source_contact_id?: string | null
          source_loan_id?: string | null
          status?: string | null
        }
        Update: {
          contact_id?: number | null
          contact_record_id?: string | null
          currency_iso_code?: string | null
          disbursal_date?: string | null
          disbursal_date_id?: number | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          loan_status?: string | null
          loan_type?: string | null
          loan_value?: number | null
          roc_donor_id?: number | null
          source_contact_id?: string | null
          source_loan_id?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_loans_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "dim_contact"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_loans_disbursal_date_id_fkey"
            columns: ["disbursal_date_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_loans_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_loans_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_loans_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
        ]
      }
      fact_observed_kpi: {
        Row: {
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          geography_id: number | null
          id: number
          kpi_id: number | null
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: string | null
          value_type: string | null
          year: number | null
          year_date_id: number | null
        }
        Insert: {
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          geography_id?: number | null
          id?: number
          kpi_id?: number | null
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          row_scope?: string | null
          update_quarter?: string | null
          updated_date?: string | null
          value?: string | null
          value_type?: string | null
          year?: number | null
          year_date_id?: number | null
        }
        Update: {
          disaggregation_level_one?: string | null
          disaggregation_level_two?: string | null
          geography_id?: number | null
          id?: number
          kpi_id?: number | null
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          row_scope?: string | null
          update_quarter?: string | null
          updated_date?: string | null
          value?: string | null
          value_type?: string | null
          year?: number | null
          year_date_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_observed_kpi_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_observed_kpi_kpi_id_fkey"
            columns: ["kpi_id"]
            isOneToOne: false
            referencedRelation: "dim_kpi"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_observed_kpi_year_date_id_fkey"
            columns: ["year_date_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
        ]
      }
      fact_post_school_support: {
        Row: {
          accommodation: string | null
          contact_id: number | null
          form: string | null
          geography_id: number | null
          id: number
          lin_business_hash: string | null
          lin_change_type: string
          lin_inserted_at: string
          lin_is_current: boolean
          lin_load_batch_id: string | null
          lin_source_file: string | null
          lin_source_row_number: number | null
          lin_source_system: string | null
          lin_superseded_at: string | null
          received_financial_support: boolean | null
          roc_donor_id: number | null
          source_academic_record_id: string | null
          source_contact_id: string | null
          year: number | null
          year_date_id: number | null
        }
        Insert: {
          accommodation?: string | null
          contact_id?: number | null
          form?: string | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          received_financial_support?: boolean | null
          roc_donor_id?: number | null
          source_academic_record_id?: string | null
          source_contact_id?: string | null
          year?: number | null
          year_date_id?: number | null
        }
        Update: {
          accommodation?: string | null
          contact_id?: number | null
          form?: string | null
          geography_id?: number | null
          id?: number
          lin_business_hash?: string | null
          lin_change_type?: string
          lin_inserted_at?: string
          lin_is_current?: boolean
          lin_load_batch_id?: string | null
          lin_source_file?: string | null
          lin_source_row_number?: number | null
          lin_source_system?: string | null
          lin_superseded_at?: string | null
          received_financial_support?: boolean | null
          roc_donor_id?: number | null
          source_academic_record_id?: string | null
          source_contact_id?: string | null
          year?: number | null
          year_date_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fact_post_school_support_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "dim_contact"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_post_school_support_geography_id_fkey"
            columns: ["geography_id"]
            isOneToOne: false
            referencedRelation: "dim_geography"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_post_school_support_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "dim_roc_donor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fact_post_school_support_roc_donor_id_fkey"
            columns: ["roc_donor_id"]
            isOneToOne: false
            referencedRelation: "view_donor_summary"
            referencedColumns: ["donor_id"]
          },
          {
            foreignKeyName: "fact_post_school_support_year_date_id_fkey"
            columns: ["year_date_id"]
            isOneToOne: false
            referencedRelation: "dim_date"
            referencedColumns: ["id"]
          },
        ]
      }
      ingest_fn_state: {
        Row: {
          attempt_count: number
          cursor: string | null
          error: string | null
          finished_at: string | null
          fn_name: string
          last_cursor_at: string | null
          last_error_at: string | null
          pages_fetched: number
          rows_fetched: number
          run_id: string
          start_row_id: number
          started_at: string | null
          status: string
          wave: number
        }
        Insert: {
          attempt_count?: number
          cursor?: string | null
          error?: string | null
          finished_at?: string | null
          fn_name: string
          last_cursor_at?: string | null
          last_error_at?: string | null
          pages_fetched?: number
          rows_fetched?: number
          run_id: string
          start_row_id?: number
          started_at?: string | null
          status?: string
          wave: number
        }
        Update: {
          attempt_count?: number
          cursor?: string | null
          error?: string | null
          finished_at?: string | null
          fn_name?: string
          last_cursor_at?: string | null
          last_error_at?: string | null
          pages_fetched?: number
          rows_fetched?: number
          run_id?: string
          start_row_id?: number
          started_at?: string | null
          status?: string
          wave?: number
        }
        Relationships: [
          {
            foreignKeyName: "ingest_fn_state_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ingest_run"
            referencedColumns: ["run_id"]
          },
        ]
      }
      ingest_run: {
        Row: {
          attempt_count: number
          current_wave: number
          error: string | null
          etl_retry_count: number
          finished_at: string | null
          last_heartbeat_at: string
          lease_expires_at: string | null
          lease_owner: string | null
          max_pages: number | null
          run_id: string
          since: string | null
          started_at: string
          started_by: string
          status: string
          updated_at: string
        }
        Insert: {
          attempt_count?: number
          current_wave?: number
          error?: string | null
          etl_retry_count?: number
          finished_at?: string | null
          last_heartbeat_at?: string
          lease_expires_at?: string | null
          lease_owner?: string | null
          max_pages?: number | null
          run_id: string
          since?: string | null
          started_at?: string
          started_by?: string
          status?: string
          updated_at?: string
        }
        Update: {
          attempt_count?: number
          current_wave?: number
          error?: string | null
          etl_retry_count?: number
          finished_at?: string | null
          last_heartbeat_at?: string
          lease_expires_at?: string | null
          lease_owner?: string | null
          max_pages?: number | null
          run_id?: string
          since?: string | null
          started_at?: string
          started_by?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      ingest_sf_counts: {
        Row: {
          captured_at: string
          rep_raw_table: string
          run_id: string
          sf_total_count: number
        }
        Insert: {
          captured_at?: string
          rep_raw_table: string
          run_id: string
          sf_total_count: number
        }
        Update: {
          captured_at?: string
          rep_raw_table?: string
          run_id?: string
          sf_total_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "ingest_sf_counts_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ingest_run"
            referencedColumns: ["run_id"]
          },
        ]
      }
    }
    Views: {
      view_cama_membership: {
        Row: {
          country: string | null
          date_joined_cama: string | null
          district: string | null
          gender: string | null
          id: number | null
          join_month: number | null
          join_month_name: string | null
          join_quarter: number | null
          join_year: number | null
          partner_school: boolean | null
          province: string | null
          school_name: string | null
          school_type: string | null
          source_contact_id: string | null
          wg_difficulty_overall: string | null
        }
        Relationships: []
      }
      view_children_supported: {
        Row: {
          attendance_issues: boolean | null
          contact_record_type: string | null
          country: string | null
          district: string | null
          donor_code: string | null
          donor_name: string | null
          form: string | null
          gender: string | null
          id: number | null
          project_code: string | null
          project_code_name: string | null
          province: string | null
          received_financial_support: boolean | null
          repeated: boolean | null
          school_name: string | null
          school_type: string | null
          source_contact_id: string | null
          wg_difficulty_overall: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_donor_summary: {
        Row: {
          active: boolean | null
          available_country: string | null
          children_supported_count: number | null
          donor_code: string | null
          donor_end_date: string | null
          donor_id: number | null
          donor_name: string | null
          donor_start_date: string | null
          grants_count: number | null
          guides_count: number | null
          loans_count: number | null
        }
        Relationships: []
      }
      view_grants: {
        Row: {
          amount_given: number | null
          country: string | null
          district: string | null
          donor_code: string | null
          donor_name: string | null
          gender: string | null
          grant_date: string | null
          grant_month: number | null
          grant_month_name: string | null
          grant_quarter: number | null
          grant_status: string | null
          grant_type: string | null
          grant_year: number | null
          id: number | null
          province: string | null
          source_contact_id: string | null
          source_grant_id: string | null
          wg_difficulty_overall: string | null
        }
        Relationships: []
      }
      view_guide_assignment: {
        Row: {
          country: string | null
          date_joined_guide_programme: string | null
          date_left_guide_programme: string | null
          district: string | null
          donor_code: string | null
          donor_name: string | null
          gender: string | null
          guide_dropout_reason: string | null
          guide_specialty: string | null
          guide_status: string | null
          guide_type: string | null
          id: number | null
          joined_month: number | null
          joined_month_name: string | null
          joined_quarter: number | null
          joined_year: number | null
          left_month: number | null
          left_month_name: string | null
          left_quarter: number | null
          left_year: number | null
          province: string | null
          school_name: string | null
          school_type: string | null
          source_contact_id: string | null
          trained_in_climate_education: boolean | null
          wg_difficulty_overall: string | null
        }
        Relationships: []
      }
      view_kpi_benchmarks: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: number | null
          value_type: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_kpi_counts: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: number | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_kpi_cumulative: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: number | null
          value_type: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_kpi_detail: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: number | null
          value_type: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_kpi_milestones: {
        Row: {
          country: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          kpi_group: string | null
          kpi_no: string | null
          lin_inserted_at: string | null
          lin_load_batch_id: string | null
          value: number | null
          value_type: string | null
          year: number | null
        }
        Relationships: []
      }
      view_kpi_percentages: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value_pct: number | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_kpi_subtotals: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: number | null
          value_type: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_kpi_targets: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: number | null
          value_type: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_level_one_kpis: {
        Row: {
          annual_newly_supported: string | null
          country: string | null
          disaggregation_gender: string | null
          fund_type: string | null
          gender: string | null
          id: number | null
          indicator: string | null
          kpi_group: string | null
          kpi_id: string | null
          school_level: string | null
          value: number | null
          year: number | null
          year_date: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_loans: {
        Row: {
          contact_record_id: string | null
          country: string | null
          currency_iso_code: string | null
          disbursal_date: string | null
          disbursal_month: number | null
          disbursal_month_name: string | null
          disbursal_quarter: number | null
          disbursal_year: number | null
          district: string | null
          donor_code: string | null
          donor_name: string | null
          gender: string | null
          id: number | null
          loan_status: string | null
          loan_status_raw: string | null
          loan_type: string | null
          loan_value: number | null
          province: string | null
          source_contact_id: string | null
          source_loan_id: string | null
          wg_difficulty_overall: string | null
        }
        Relationships: []
      }
      view_observed_kpi: {
        Row: {
          country: string | null
          definition: string | null
          disaggregation_level_one: string | null
          disaggregation_level_two: string | null
          id: number | null
          indicator: string | null
          indicator_frequency: string | null
          indicator_start: string | null
          kpi_group: string | null
          kpi_id: string | null
          lin_source_row_number: number | null
          row_scope: string | null
          update_quarter: string | null
          updated_date: string | null
          value: string | null
          value_type: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_post_school_support: {
        Row: {
          accommodation: string | null
          country: string | null
          district: string | null
          donor_code: string | null
          donor_name: string | null
          form: string | null
          gender: string | null
          id: number | null
          province: string | null
          received_financial_support: boolean | null
          source_contact_id: string | null
          wg_difficulty_overall: string | null
          year: number | null
          year_date: string | null
          year_month: number | null
          year_month_name: string | null
          year_quarter: number | null
        }
        Relationships: []
      }
      view_school_map: {
        Row: {
          active_on_bursary: boolean | null
          active_partner_school: boolean | null
          country: string | null
          cpp_in_place: boolean | null
          district: string | null
          donor_code: string | null
          donor_name: string | null
          gea_school: boolean | null
          id: number | null
          latitude: number | null
          longitude: number | null
          monitoring_school: boolean | null
          province: string | null
          roc_geography_code: string | null
          roc_geography_name: string | null
          school_name: string | null
          school_type: string | null
          snf_only: boolean | null
          source_school_id: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      configure_ingest_cron: {
        Args: {
          p_resume_schedule?: string
          p_service_role_key?: string
          p_supabase_url: string
          p_trigger_schedule?: string
          p_vault_secret_name?: string
        }
        Returns: undefined
      }
      count_all_kpi_rows: { Args: { p_year: number }; Returns: number }
      country_is_excluded: { Args: { p_country: string }; Returns: boolean }
      disable_ingest_cron: { Args: never; Returns: undefined }
      district_report_children: {
        Args: { p_district: string; p_year?: number }
        Returns: {
          bursary_boys: number
          bursary_girls: number
          tertiary_girls: number
          total_boys: number
          total_girls: number
        }[]
      }
      district_report_finance: {
        Args: { p_district: string; p_year?: number }
        Returns: {
          grants_boys: number
          grants_count: number
          grants_girls: number
          grants_total: number
          loans_boys: number
          loans_count: number
          loans_girls: number
          loans_total: number
        }[]
      }
      district_report_guides_by_type: {
        Args: { p_district: string }
        Returns: {
          active_count: number
          guide_type: string
        }[]
      }
      district_report_people: {
        Args: { p_district: string }
        Returns: {
          active_guides: number
          cama_members: number
          total_guides: number
        }[]
      }
      district_report_schools: {
        Args: { p_district: string }
        Returns: {
          active_partner_schools: number
          top_schools: string
        }[]
      }
      etl_apply_deletions: {
        Args: { p_deletion_run_id?: string }
        Returns: {
          objects_processed: number
          rows_soft_deleted: number
        }[]
      }
      etl_load_dim_contact: { Args: never; Returns: undefined }
      etl_load_dim_geography: { Args: never; Returns: undefined }
      etl_load_dim_geography_kpi: { Args: never; Returns: undefined }
      etl_load_dim_roc_donor: { Args: never; Returns: undefined }
      etl_load_dim_roc_donor_activity: { Args: never; Returns: undefined }
      etl_load_dim_roc_geography: { Args: never; Returns: undefined }
      etl_load_dim_roc_project_code: { Args: never; Returns: undefined }
      etl_load_dim_school: { Args: never; Returns: undefined }
      etl_load_fact_cama_membership: { Args: never; Returns: undefined }
      etl_load_fact_children_supported: { Args: never; Returns: undefined }
      etl_load_fact_grants: { Args: never; Returns: undefined }
      etl_load_fact_guide_assignment: { Args: never; Returns: undefined }
      etl_load_fact_level_one_kpis: { Args: never; Returns: undefined }
      etl_load_fact_loans: { Args: never; Returns: undefined }
      etl_load_fact_observed_kpi: { Args: never; Returns: undefined }
      etl_load_fact_post_school_support: { Args: never; Returns: undefined }
      etl_reschedule_salesforce_run: {
        Args: { p_run_id: string }
        Returns: undefined
      }
      etl_run_salesforce: {
        Args: {
          p_batch_id?: string
          p_source_file?: string
          p_source_system?: string
        }
        Returns: string
      }
      etl_run_salesforce_bg: { Args: { p_run_id: string }; Returns: undefined }
      etl_run_staging: { Args: never; Returns: undefined }
      etl_run_warehouse: { Args: never; Returns: undefined }
      etl_schedule_salesforce_run: {
        Args: { p_run_id: string }
        Returns: undefined
      }
      etl_stage_academic_record: { Args: never; Returns: undefined }
      etl_stage_all_kpis: { Args: never; Returns: undefined }
      etl_stage_cama_members: { Args: never; Returns: undefined }
      etl_stage_contacts: { Args: never; Returns: undefined }
      etl_stage_countries: { Args: never; Returns: undefined }
      etl_stage_dimension_1_roc: { Args: never; Returns: undefined }
      etl_stage_dimension_2_roc: { Args: never; Returns: undefined }
      etl_stage_dimension_3_roc: { Args: never; Returns: undefined }
      etl_stage_dimension_4_roc: { Args: never; Returns: undefined }
      etl_stage_districts: { Args: never; Returns: undefined }
      etl_stage_grant_recipients: { Args: never; Returns: undefined }
      etl_stage_guides: { Args: never; Returns: undefined }
      etl_stage_level_one_kpis: { Args: never; Returns: undefined }
      etl_stage_loan_recipients: { Args: never; Returns: undefined }
      etl_stage_post_school_clients: { Args: never; Returns: undefined }
      etl_stage_schools: { Args: never; Returns: undefined }
      get_all_kpi_rows: {
        Args: { p_limit?: number; p_offset?: number; p_year: number }
        Returns: {
          countries: Json
          disaggregation1: string
          disaggregation2: string
          indicator: string
          indicator_group: string
          kpi_no: string
          row_id: number
          total: string
          updated_date: string
          value_type: string
        }[]
      }
      ingest_claim_run: {
        Args: { p_lease_ms?: number; p_lease_owner: string }
        Returns: {
          current_wave: number
          max_pages: number
          run_id: string
          since: string
          status: string
          updated_at: string
        }[]
      }
      ingest_finish_run: {
        Args: {
          p_error?: string
          p_lease_owner: string
          p_run_id: string
          p_status: string
        }
        Returns: undefined
      }
      ingest_heartbeat: {
        Args: { p_lease_ms?: number; p_lease_owner: string; p_run_id: string }
        Returns: undefined
      }
      ingest_release_run: {
        Args: { p_error?: string; p_lease_owner: string; p_run_id: string }
        Returns: undefined
      }
      ingest_start_run: {
        Args: {
          p_lease_ms?: number
          p_lease_owner?: string
          p_max_pages?: number
          p_run_id: string
          p_since?: string
          p_started_by?: string
        }
        Returns: {
          current_wave: number
          max_pages: number
          run_id: string
          since: string
          status: string
          updated_at: string
        }[]
      }
      is_admin: { Args: never; Returns: boolean }
      kpi_definitions_load: {
        Args: {
          p_batch_id: string
          p_rows: Json
          p_source_file: string
          p_uploaded_by: string
        }
        Returns: Json
      }
      kpi_delete_year: { Args: { p_year: number }; Returns: Json }
      kpi_milestone_chart_key: {
        Args: {
          p_disagg1: string
          p_disagg2: string
          p_indicator: string
          p_kpi_group: string
        }
        Returns: string
      }
      kpi_milestone_groups: {
        Args: never
        Returns: {
          kpi_group: string
        }[]
      }
      kpi_milestone_indicators: {
        Args: { p_kpi_group: string }
        Returns: {
          indicator: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      kpi_milestone_report: {
        Args: { p_indicator: string; p_kpi_group: string; p_year: number }
        Returns: {
          actual_value: number
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          milestone_value: number
          value_type: string
        }[]
      }
      kpi_milestone_years: {
        Args: never
        Returns: {
          year: number
        }[]
      }
      kpi_report_all_groups: {
        Args: never
        Returns: {
          kpi_group: string
        }[]
      }
      kpi_report_all_indicators: {
        Args: { p_kpi_group: string }
        Returns: {
          indicator: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      kpi_report_country: { Args: { p_district: string }; Returns: string }
      kpi_report_groups: {
        Args: { p_country: string; p_year: number }
        Returns: {
          kpi_group: string
        }[]
      }
      kpi_report_indicator_detail: {
        Args: {
          p_country: string
          p_indicator: string
          p_kpi_group: string
          p_year: number
        }
        Returns: {
          definition: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          source_kpi_id: string
          value: string
          value_type: string
        }[]
      }
      kpi_report_indicator_trend: {
        Args: { p_country: string; p_indicator: string; p_kpi_group: string }
        Returns: {
          disaggregation_level_one: string
          disaggregation_level_two: string
          value: string
          value_type: string
          year: number
        }[]
      }
      kpi_report_indicator_trend_all_countries: {
        Args: { p_indicator: string; p_kpi_group: string }
        Returns: {
          country: string
          disaggregation_level_one: string
          disaggregation_level_two: string
          value: string
          value_type: string
          year: number
        }[]
      }
      kpi_report_indicators: {
        Args: { p_country: string; p_kpi_group: string; p_year: number }
        Returns: {
          indicator: string
          short_label: string
          source_kpi_id: string
        }[]
      }
      kpi_report_years: {
        Args: { p_country: string }
        Returns: {
          year: number
        }[]
      }
      kpi_trend_chart_key: {
        Args: {
          p_disagg1: string
          p_disagg2: string
          p_indicator: string
          p_kpi_group: string
        }
        Returns: string
      }
      kpi_upload_all: {
        Args: {
          p_batch_id: string
          p_source_file: string
          p_uploaded_by: string
          p_year: number
        }
        Returns: Json
      }
      kpi_upload_level_one: {
        Args: {
          p_batch_id: string
          p_source_file: string
          p_uploaded_by: string
        }
        Returns: Json
      }
      milestone_upload: {
        Args: {
          p_batch_id: string
          p_source_file: string
          p_uploaded_by: string
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
  rep_portal: {
    Enums: {},
  },
  rep_raw: {
    Enums: {},
  },
  rep_warehouse: {
    Enums: {},
  },
} as const

