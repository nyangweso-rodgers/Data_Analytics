-------------------------------------- Global Dashboard - Gross Margin Report --------------------------------------------
with
currency_conversion_table as (SELECT * FROM `kyosk-prod.erp_reports.upload_currency_conversion_v2`  where ex_rate not in ('BUDGET RATE (2022)')),
sales_invoice_with_index as (SELECT *, row_number()over(partition by name order by modified desc) as index FROM `kyosk-prod.erp_reports.sales_invoice` ),
delivery_note_with_index as (
                              SELECT *, row_number()over(partition by name order by modified desc) as index FROM `kyosk-prod.erp_reports.delivery_note`
                              where workflow_state in ('PAID', 'DELIVERED')
                              --and company = 'KYOSK DIGITAL SERVICES LTD (KE)'
                              --and posting_date between '2022-10-01' and '2022-10-31'
                            ),
delivery_note_with_items as (
                              select distinct dn.posting_date,
                              dn.company,
                              dn.territory,
                              dn.name as delivery_note,
                              dni.name,
                              dni.item_group,
                              dni.item_code as item_name_of_delivery_name,
                              dni.uom as uom_of_delivery_note,
                              dni.qty as qty_of_delivery_note
                              from delivery_note_with_index dn, unnest(items) dni
                              where index = 1
                              ),
delivery_note_with_packed_items as (
                                    select distinct dn.name as delivery_note,
                                    pi.parent_detail_docname,
                                    pi.item_name as item_name_of_packed_item,
                                    pi.uom as uom_of_packed_item,
                                    pi.incoming_rate,
                                    pi.qty as qty_of_packed_item,
                                    pi.qty * pi.incoming_rate as total_incoming_rate
                                    from delivery_note_with_index dn,unnest(packed_items) pi
                                    where index = 1
                                    order by 1
                                    ),
sales_invoice_with_items as (
                              select distinct si.name as sales_invoice,
                              sii.dn_detail,
                              sii.base_net_amount as base_net_amount_of_sales_invoice
                              from sales_invoice_with_index si, unnest(items) sii
                              where index = 1
                              ),
gross_margin_report as (
                        select dnwi.*,
                        dnwpi.*except(delivery_note), 
                        siwi.*, 
                        siwi.base_net_amount_of_sales_invoice / cct.ex_rate_amount as base_net_amount_of_sales_invoice_in_usd,
                        (siwi.base_net_amount_of_sales_invoice - dnwpi.total_incoming_rate) as gross_margin,
                        (siwi.base_net_amount_of_sales_invoice - dnwpi.total_incoming_rate) / cct.ex_rate_amount as gross_margin_in_usd
                        from delivery_note_with_items dnwi
                        left join delivery_note_with_packed_items dnwpi on dnwi.name = dnwpi.parent_detail_docname
                        left join sales_invoice_with_items siwi on dnwpi.parent_detail_docname = siwi.dn_detail
                        left join currency_conversion_table cct on dnwi.company = cct.company and dnwi.posting_date between cct.start_date and cct.end_date  
                        where sales_invoice is not null
                        )
select * from gross_margin_report
--where FORMAT_DATE('%Y%m%d', posting_date) between @DS_START_DATE and @DS_END_DATE