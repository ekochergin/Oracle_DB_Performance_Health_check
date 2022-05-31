/*
  A script to check the database performance health of an instance which is on version 11
  
  It is intended to be launched via command line + sqlplus, like "sqlplus -s user/pass@database @this_script.sql > output_file_name.htm", 
  so the output is to be forwarded to a file. Don't forget the "-s" parameter to turn off all the sqlplus pointless notifications
  
  It is assumed that user has accces to all necessary dba_% objects
  
  Version: 1.2.0
  Last changed on: 14 September 2020
  Author:          Evgenii Kochergin
  email:           ekochergin85@gmail.com
  
  NOTE: Some part of the report may crash with "ORA 20001 - 'XXXXXX' Invalid identifier" where 'XXXXXX' some scary identifier which seems to be not humanreadable.
        This happens when dbms_stats package analyzes dba_recyclebin contents. Nature of such a problem is not clear to me. Solution would be to purge dba_recyclebin:
        
        !! PLEASE EXECUTE THE FOLOWING ONLY IF YOU KNOW WHAT YOU ARE DOING !! as I'm not responsible for any damage it might cause to your db
        1. connect as sys
        2. purge dba_recyclebin
        
*/

set serveroutput on
set linesize 32767

declare 
  type varchar2_t is table of varchar2(32000); -- being used in print_plsql_table function

  l_css varchar2(32767); -- keeps all te CSS code. It gets populated in main begin-end block
  l_js varchar2(32767);  -- same thing for Javascript code
  
  g_max_frag_idx_cnt constant number := 50; -- max number of fragmented indexes to display
  g_max_frag_tab_cnt constant number := 50; -- max number of fragmented tables to show
  g_max_stats_cnt constant number := 20; -- max number of performance stats to display
  
  /*
  prints head and title tags.
  Parameter:
      p_title_name is the value that goes into <title> tag
  */
  procedure print_header(p_title_name in varchar2)
  is
  begin
    dbms_output.put_line(htf.headOpen);
    dbms_output.put_line(htf.title(p_title_name));
    dbms_output.put_line(htf.style(l_css));
    dbms_output.put_line(htf.headClose);
  exception
    when others then
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>An error occured while printing head of the document: ' || sqlerrm || '</div>');
  end print_header;
  
  /*
  function returns concatenated bind values captured for a query covered with div tags having a unique id
    parameters: p_sqlid         = v$sql.sql_id
                p_child_address = v$sql.child_address
  */
  function get_binds(p_sqlid in v$sql_bind_capture.sql_id%type, p_child_address in v$sql_bind_capture.child_address%type) return varchar2
  is
    binds_div varchar2(32000);
  begin

    select listagg( case bc.was_captured
                   when 'YES' then 
                     bc.name || '(' || bc.datatype_string || '): ' || bc.value_string || ';' || chr(10)
                   else '' end) within group(order by bc.name)
      into binds_div
      from (select distinct sql_id, child_address, name, datatype_string, value_string, was_captured from v$sql_bind_capture) bc
     where bc.sql_id = p_sqlid 
       and bc.child_address = p_child_address
     group by bc.sql_id,
              bc.child_address;
            
    return binds_div;
  exception
    when no_data_found then
      return ' ';
    when others then
      dbms_output.put_line('<div class="error">Error while getting binds for sql_id: ' ||p_sqlid || ', child_address: ' || p_child_address || '. Error text: ' ||sqlerrm || '</div>');
      return ' ';
  end get_binds;
  
  /*
  prints a clob to the output
  */
  procedure print_clob(p_clob in clob)
  is
    l_step number := 2000;
    l_start_pos number := 1;
    l_symb_in_line number := 0;
    l_next_space number := l_step + 1;
  begin
    loop
      exit when l_start_pos > dbms_lob.getlength(p_clob);
      if l_symb_in_line >= 30000 then
        l_next_space := dbms_lob.instr(p_clob, ' ', l_start_pos);
        if l_next_space >= l_start_pos and l_next_space <= (l_start_pos + l_step) then
          dbms_output.put_line(dbms_lob.substr(p_clob, l_next_space - l_start_pos, l_start_pos));
          l_start_pos := l_next_space;
          l_symb_in_line := 0;
          continue;
        end if;
      end if;
      dbms_output.put(dbms_lob.substr(p_clob, l_step, l_start_pos));
      l_start_pos := l_start_pos + l_step;
      l_symb_in_line := l_symb_in_line + l_step;
    end loop;
    dbms_output.new_line();
  end print_clob;
  
  /*
  escapes html symbols in a clob
  */
  function escape_html_clob(p_clob in clob) return clob
  is
    l_step number := 4000;
    l_start_pos number := 1;
    l_result clob := ' ';
  begin
    loop
      exit when l_start_pos > dbms_lob.getlength(p_clob);
      l_result := l_result || htf.escape_sc(dbms_lob.substr(p_clob, l_step, l_start_pos));
      l_start_pos := l_start_pos + l_step;
    end loop;
    return l_result;
  end escape_html_clob;
  
  /*
  a routine to print out a plsql table as an html table
  parameters: p_id - the id html tag for the table
              p_headers - a bunch of th tags to be printed within thead tag
              p_table   - table of varchar2(32000), containing valid <tr>s only
              p_classes - list of css-classes associated with the table (varchar2, default is null)
  */
  function print_plsql_table(p_id in varchar2, p_headers in varchar2, p_table in varchar2_t, p_classes in varchar2 default null) return number
  is
  begin
    if p_table.count > 0 then
      dbms_output.put_line('<table id="' || p_id || '" class="' || p_classes || '">');
      dbms_output.put_line('<thead>' || p_headers || '</thead>');
      dbms_output.put_line('<tbody>');
      for i in 1..p_table.count loop
        dbms_output.put_line(p_table(i));
      end loop;
      dbms_output.put_line('</tbody></table>');
    else
      -- the "a" within span is to show a check mark using "webdings" font (see CSS for details)
      dbms_output.put_line('<div class="news good-news"><span class="icon-span">a</span>Nothing found!</div>');
    end if;
    
    return p_table.count;
  end;
  
  /*
  prints a simple html-table, puts a "good-news" div when nothing found
  parameters: p_id - the id html tag for the table
              p_headers - a bunch of th tags to be printed within thead tag
              p_cursor - sys_refcursor to get data. It must return just a varchar-row containing valid html table row (<tr>...</tr>)
              p_classes - list of css-classes associated with the table (varchar2, default is null)
  returns rowcount of a p_cusor for further analysis if needed
  */
  function simple_html_table(p_id in varchar2, p_headers in varchar2, p_cursor in sys_refcursor, p_classes in varchar2 default null) return number
  is
    tr_lines varchar2_t;
  begin
    fetch p_cursor bulk collect into tr_lines;
    close p_cursor;
    
    return print_plsql_table(p_id, p_headers, tr_lines, p_classes);
  exception
    when others then
      if p_cursor%isopen then
        close p_cursor;
      end if;
  end simple_html_table;
  
  /*
  prints a button that get attached to a table and is to gather all the fix-commands from that table into a popup, 
  so the user doesn't have to click every table row manually to get all fix commands
  Parameter:
      p_id - html-id of the table the button will be attached to
  */
  procedure print_collect_commands_button(p_id varchar2, p_delimiter varchar2 default null)
  is
    l_parameters varchar2(1000);
  begin
    l_parameters := '''' || p_id || '''';
	if p_delimiter is not null then
	  l_parameters := l_parameters || ', ''' || p_delimiter || '''';
	end if;
  
    dbms_output.put_line('<div class="collect-cmd-btn">');
    dbms_output.put_line('<button class="collect-cmd" onclick="collectCommands(' || l_parameters || ')">Show all commands in a popup</button>');
    dbms_output.put_line('</div>');
  end;
  
  /*
  Prints out fragmentation stats for top 50 indexes sorted by the following relation "idx_size / table_size"
  */
  
  procedure print_frag_indexes is
    l_idx_cnt number := 0;
    l_dummy number;
    l_fix_command varchar2(32000);
    
    l_ratio number;
    l_height index_stats.height%type;
    l_lf_blks index_stats.lf_blks%type;
    l_lf_rows index_stats.lf_rows%type;
    
    l_indx_stats varchar2_t := varchar2_t();
  
    cursor c_frag_idx is 
      select i.owner, i.index_name, round(idx_seg.blocks / tab_seg.blocks * 100, 2) index_size_pct, idx_seg.bytes / 1024 / 1024 idx_size_mb, tab_seg.bytes / 1024 / 1024 tab_size_mb
        from dba_indexes i,
             dba_tables t,
             dba_segments idx_seg,
             dba_segments tab_seg
       where t.owner = i.owner and t.table_name = i.table_name
         and idx_seg.owner = i.owner and idx_seg.segment_name = i.index_name
         and tab_seg.owner = t.owner and tab_seg.segment_name = t.table_name
         and t.owner not in ('SYS', 'SYSTEM', 'SYSMAN', 'DBSNMP', 'ANONYMOUS', 'APEX_030200', 'APEX_PUBLIC_USER', 
                             'APPQOSSYS', 'BI', 'CTXSYS', 'DIP', 'DVSYS', 'EXFSYS', 'FLOWS_FILES',
                             'HR', 'IX', 'LBACSYS', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OE', 'ORDPLUGINS', 
                             'ORDSYS', 'ORDDATA', 'OUTLN', 'ORACLE_OCM', 'OWBSYS', 'OWBSYS_AUDIT',
                             'PM', 'SCOTT', 'SH', 'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 
                             'SPATIAL_WFS_ADMIN_USR', 'WMSYS', 'XDB', 'APEX_040200', 'OLAPSYS')
         and t.blocks > 10000
         and round(idx_seg.blocks / tab_seg.blocks * 100, 2) > 20
       order by idx_seg.blocks / tab_seg.blocks desc;
  
  begin
    for f_idx in c_frag_idx loop
      exit when l_idx_cnt = g_max_frag_idx_cnt;
      -- Now, analyze all the indexes we've found
      declare
        ignore_index exception;
      begin
        begin
          execute immediate 'analyze index ' || f_idx.owner || '.' || f_idx.index_name || ' validate structure';
        exception
          when others then
            raise ignore_index; -- it fails often because of index appeared to be busy
        end;
        -- l_ratio = (number of deleted rows in an index / number of index rows) in percents
        select round((del_lf_rows/lf_rows) * 100, 2), height, lf_blks, lf_rows
          into l_ratio, l_height, l_lf_blks, l_lf_rows
          from index_stats
         where lf_rows > 0;
      exception
        when no_data_found or ignore_index then
          l_ratio := null;   
          l_height := null;
          l_lf_rows := null; 
          l_lf_blks := null;
      end;
      
      if l_ratio > 20 or l_height >= 4 or l_lf_rows < l_lf_blks then
        l_idx_cnt := l_idx_cnt + 1;
        
        /*
        Q: why the coalesce is here when shrink space is enough for defragmentation?
        A: shrink space locks the table for the whole it is being executed, whereas coalesce does not. 
           So the idea is to make as much work as possible without causing any lock in the db
        */
        
        l_fix_command := 'alter index ' || f_idx.owner || '.' || f_idx.index_name || ' coalesce;<br>' || 
                         'alter index ' || f_idx.owner || '.' || f_idx.index_name || ' shrink space;';
        l_indx_stats.extend;
        l_indx_stats(l_indx_stats.count) := '<tr>' ||
                                              '<td class="left-align">' || f_idx.owner || '</td><td class="left-align">' || f_idx.index_name || 
                                              '</td><td class="right-align">' || f_idx.idx_size_mb || '</td><td class="right-align">' || f_idx.tab_size_mb ||
                                              '</td><td class="right-align">' || l_ratio || '</td><td class="right-align">' || l_height || 
                                              '</td><td class="right-align">' || l_lf_blks || '</td><td class="right-align">' || l_lf_rows || '</td>' ||
                                              '</td><td class="center-align"><a href="#" onclick="showCommand(''' || l_fix_command || ''')">Show command</a>' || '</td>' ||
                                            '</tr>';
      end if;
    end loop;
    
    l_dummy := print_plsql_table('frag-indexes-stats',
                               '<th>Owner</th><th>Index name</th><th>Index size</th><th>Tab size</th><th>ratio</th><th>Tree''s height</th><th>Data blocks</th><th>Values</th><th>How to fix</th',
                               l_indx_stats);
  end print_frag_indexes;
  
  /*
  Prints table fragmentation statistics for 50 most fragmented tables
  */

  procedure print_frag_tables
  is
    l_fix_command varchar2(32000);
    frag_stats varchar2_t := varchar2_t();
    dummy number;
  
    unf_blocks  number;  unf_bytes  number;
    fs1_blocks  number;  fs1_bytes  number;
    fs2_blocks  number;  fs2_bytes  number;
    fs3_blocks  number;  fs3_bytes  number;
    fs4_blocks  number;  fs4_bytes  number;
    full_blocks number;  full_bytes number;

    -- 50 most fragmented tables    
    cursor c_frag_tables is
      select * 
      from (select round((1 - (dt.avg_row_len * dt.num_rows) / (ds.blocks * p.value)) * 100, 2) frag_rate_pct,
                   dt.table_name,
                   ds.blocks,
                   dt.owner
              from dba_tables dt,
                   dba_segments ds,
                   v$parameter p,
                   dba_tab_statistics dts
             where ds.owner = dt.owner
               and ds.segment_name = dt.table_name
               and dt.owner not in ('SYS', 'SYSTEM', 'SYSMAN', 'DBSNMP', 'ANONYMOUS', 'APEX_030200', 'APEX_PUBLIC_USER', 
                                    'APPQOSSYS', 'BI', 'CTXSYS', 'DIP', 'DVSYS', 'EXFSYS', 'FLOWS_FILES',
                                    'HR', 'IX', 'LBACSYS', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OE', 'ORDPLUGINS', 
                                    'ORDSYS', 'ORDDATA', 'OUTLN', 'ORACLE_OCM', 'OWBSYS', 'OWBSYS_AUDIT',
                                    'PM', 'SCOTT', 'SH', 'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 
                                    'SPATIAL_WFS_ADMIN_USR', 'WMSYS', 'XDB', 'APEX_040200', 'OLAPSYS')
               and ds.blocks > 10000 -- filter tiny tables out
               and dt.num_rows > 0 
               and dt.avg_row_len > 0
               and p.name = 'db_block_size'
               and dts.table_name (+) = dt.table_name
               and dts.owner (+) = dt.owner
               and nvl(dts.stale_stats, 'NO') = 'NO'
               and round((1 - (dt.avg_row_len * dt.num_rows)/(ds.blocks * p.value)) * 100, 2) > 20 -- don't let table with small fragm. rate to bother us
             order by frag_rate_pct desc)
         where rownum <= g_max_frag_tab_cnt;
  begin
    for frag_tab in c_frag_tables loop
      -- get the detailed fragmentation info
      dbms_space.space_usage(frag_tab.owner, frag_tab.table_name, 'TABLE',
                             unf_blocks, unf_bytes,
                             fs1_blocks, fs1_bytes, 
                             fs2_blocks, fs2_bytes,
                             fs3_blocks, fs3_bytes, 
                             fs4_blocks, fs4_bytes,
                             full_blocks, full_bytes);     
      
      /*
      Q: why the "shrink space compact" is here when "shrink space" is enough for defragmentation?
      A: shrink space locks the table for the whole time it is being executed on, whereas "shrink space compact" (aka coalesce) does not. 
         So the idea is to make as much work as possible without causing any lock in the db
      */
      l_fix_command := 'alter table ' || frag_tab.owner || '.' || frag_tab.table_name || ' enable row movement;<br>';
      l_fix_command := l_fix_command || 'alter table ' || frag_tab.owner || '.' || frag_tab.table_name || ' shrink space compact;<br>';
      l_fix_command := l_fix_command || 'alter table ' || frag_tab.owner || '.' || frag_tab.table_name || ' shrink space;<br>';
      l_fix_command := l_fix_command || 'alter table ' || frag_tab.owner || '.' || frag_tab.table_name || ' disable row movement;';
                                   
      -- append that data into a plsql table                     
      frag_stats.extend;
      frag_stats(frag_stats.count) := '<tr>' ||
                                        '<td class="left-align">' || frag_tab.owner || '</td><td class="left-align">' || frag_tab.table_name || '</td><td class="right-align">' || frag_tab.frag_rate_pct || '%' ||
                                        '</td><td class="right-align">' || frag_tab.blocks || '</td><td class="right-align">' || unf_blocks || 
                                        '</td><td class="right-align">' || fs1_blocks || '</td><td class="right-align">' || fs2_blocks || 
                                        '</td><td class="right-align">'  || fs3_blocks || '</td><td class="right-align">' || fs4_blocks || 
                                        '</td><td class="right-align">' || full_blocks || '</td>' ||
                                        '</td><td class="center-align"><a href="#" onclick="showCommand(''' || l_fix_command || ''')">Show command</a></td>' ||
                                      '</tr>';
    end loop;
    
    dummy := print_plsql_table('frag-table-stats', 
                               '<th>owner</th><th>table name</th><th>fragmentation rate</th>' ||
                               '<th>blocks total</th><th>unformatted blocks</th><th>0-25% free blocks</th><th>25-50% free blocks</th>' ||
                               '<th>50-75% free blocks</th><th>75-100% free blocks</th><th>full blocks</th><th>How to fix</th>',
                               frag_stats);
  end print_frag_tables;
  
  /*
  puts out sqls' performance statistic in an html table
  parameters: p_stat_name - statistic name sqls are to be sorted by 
                options:  'time' - get queries sorted by elapsed_time descending
                          'disk' - sorted by disk_reads desc
                          'logical_reads' - sorted by buffer_gets desc
                          'cpu' - sorted by cpu usage desc
  */
  
  procedure print_perf_stats_data(p_stat_name in varchar2)
  is
    -- cursor to show sqls' performance statistics. 
    cursor stats_data(p_order_by in varchar2) is
      select *
        from (select '<tr><td class="left-align">' || s.sql_id ||
                     '</td><td class="left-align">' || s.child_address ||
                     '</td><td>' || s.END_OF_FETCH_COUNT ||
                     '</td><td>' || round(s.elapsed_time / s.END_OF_FETCH_COUNT / 1000000) ||
                     '</td><td>' || round(s.disk_reads / s.END_OF_FETCH_COUNT) ||
                     '</td><td>' || round(s.buffer_gets / s.END_OF_FETCH_COUNT) ||
                     '</td><td>' || round(s.cpu_time / s.END_OF_FETCH_COUNT) ||
                     '</td><td class="left-align">' || s.module ||
                     '</td><td class="center-align"><a href="#" onclick="gatherInfo(''' || s.sql_id || ''', ''' || s.child_address || ''')">Show query info</a>' ||
                     '</td></tr>' as val,
                     s.sql_fulltext,
                     s.sql_id,
                     s.child_address
                from v$sql s
               where END_OF_FETCH_COUNT > 0
               order by case p_order_by 
                          when 'time' then round(s.elapsed_time / s.END_OF_FETCH_COUNT / 1000000)
                          when 'disk' then round(s.disk_reads / s.END_OF_FETCH_COUNT)
                          when 'logical_reads' then round(s.buffer_gets / s.END_OF_FETCH_COUNT)
                          when 'cpu' then round(s.cpu_time / s.END_OF_FETCH_COUNT)
                        end desc)
       where rownum <= g_max_stats_cnt;
    
    queries       clob;  -- stores all the sqls
    l_query_binds varchar2(32767) := ''; -- bind variables' values for a query
    l_all_binds   varchar2(32767); -- all captured values for all variables (I'm sure there is enough space for capturing binds' data)
    -- variables need for debug info
    l_current_sql_id v$sql.sql_id%type;
    l_child_address v$sql.child_address%type;
  begin
    dbms_output.put_line('<table id="sql-perf-' || p_stat_name || '">');
    dbms_output.put_line('<thead><tr><th>sql_id</th><th>child_address</th><th>exec. count</th><th>avg elapsed time, sec</th><th>avg disk reads</th><th>avg logical reads</th><th>avg cpu usage</th><th>module name</th><th>Info</th</tr></thead>');
    for line in stats_data(p_stat_name) loop
      l_current_sql_id := line.sql_id;
      l_child_address := line.child_address;
      dbms_output.put_line(line.val); -- puts out the table row

      -- checks whether there are values for bind variables captured. saves them in a separate div if yes.
      l_query_binds := get_binds(line.sql_id, line.child_address);      
      if length(l_query_binds) > 1 then
        l_all_binds := l_all_binds || '<div id="binds-' || line.sql_id || '-' || to_char(line.child_address) || '" class="hidden">' || l_query_binds || '</div>';
      end if;
      l_query_binds := '';
      
      -- saves query text into a standalone div in a clob where other sqls are being stored
      queries := queries || '<div id="sql-' || line.sql_id || '-' || to_char(line.child_address) || '" class="hidden">' || escape_html_clob(line.sql_fulltext) || '</div>';
    end loop;
    dbms_output.put_line('</table>');
    dbms_output.put_line(l_all_binds);
    print_clob(queries);
  exception
    when others then
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>');
      dbms_output.put_line('Error in print_perf_stats_data: ' || sqlerrm);
      dbms_output.put_line('<p>Parameters:</p>');
      dbms_output.put_line('<p>  p_stat_name: ' || p_stat_name || ';</p>' || chr(10) ||
                           '<p>  sql_id: '|| l_current_sql_id || ';</p>' || chr(10) ||
                           '<p>  child_address: ' || l_child_address ||';</p>');
      dbms_output.put_line('</div>');
  end print_perf_stats_data;
  
  /*
  Prints table that have stale statistic
  */
  procedure print_stale_tables
  is 
    c_stale_tabs sys_refcursor;
    dummy number; 
  begin
    open c_stale_tabs for select '<tr><td class="left-align">'   || owner ||
                                 '</td><td class="left-align">'  || table_name ||
                                 '</td><td class="left-align">'  || object_type ||
                                 '</td><td class="right-align">' || to_char(last_analyzed, 'dd.mm.yyyy hh24:mi:ss') ||
                                 '</td><td class="center-align"><a href=# onclick="showCommand(''begin dbms_stats.gather_table_stats(\''' || owner || '\'', \''' || table_name || '\''' ||
                                   case when partition_name is not null then ', \''' || partition_name || '\''' end || '); end;'')">Show command</a>' ||
                                 '</td></tr>'
                            from dba_tab_statistics 
                           where stale_stats = 'YES'
                             and owner not in ('SYS', 'SYSTEM', 'SYSMAN', 'DBSNMP', 'ANONYMOUS', 'APEX_030200', 'APEX_PUBLIC_USER', 
                                               'APPQOSSYS', 'BI', 'CTXSYS', 'DIP', 'DVSYS', 'EXFSYS', 'FLOWS_FILES',
                                               'HR', 'IX', 'LBACSYS', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OE', 'ORDPLUGINS', 
                                               'ORDSYS', 'ORDDATA', 'OUTLN', 'ORACLE_OCM', 'OWBSYS', 'OWBSYS_AUDIT',
                                               'PM', 'SCOTT', 'SH', 'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 
                                               'SPATIAL_WFS_ADMIN_USR', 'WMSYS', 'XDB', 'APEX_040200', 'OLAPSYS');
    dummy := simple_html_table('stale-tables', 
                               '<th> owner </th><th> table name </th><th> object type </th><th> last analyzed date </th><th> how to fix </th>', 
                               c_stale_tabs);
  exception
    when others then 
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>');
      dbms_output.put_line('There is a following error in printing stale tables procedure: ' || sqlerrm);
      dbms_output.put_line('</div>');
  end print_stale_tables;

  /*
  Prints indexes that have stale statistic
  */
  procedure print_stale_indexes
  is
    c_stale_indxs sys_refcursor;
    dummy number;
  begin
    open c_stale_indxs for select '<tr><td class="left-align">'  || owner ||
                                  '</td><td class="left-align">' || index_name ||
                                  '</td><td class="left-align">' || table_owner || 
                                  '</td><td class="left-align">' || table_name ||
                                  '</td><td class="left-align">' || object_type ||
                                  '</td><td class="right-align">' || to_char(last_analyzed, 'dd.mm.yyyy hh24:mi:ss') ||
                                  '</td><td class="center-align">' || 
                                    '<a href=# onclick="showCommand(''begin dbms_stats.gather_index_stats(\''' || owner || '\'', \''' || index_name || '\''' || 
                                    case when partition_name is not null then ', \''' || partition_name || '\''' end || '); end;'')"' || '>Show command</a>' ||
                                  '</td></tr>'     
                             from dba_ind_statistics 
                            where stale_stats = 'YES'
                              and owner not in ('SYS', 'SYSTEM', 'SYSMAN', 'DBSNMP', 'ANONYMOUS', 'APEX_030200', 'APEX_PUBLIC_USER', 
                                                'APPQOSSYS', 'BI', 'CTXSYS', 'DIP', 'DVSYS', 'EXFSYS', 'FLOWS_FILES',
                                                'HR', 'IX', 'LBACSYS', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OE', 'ORDPLUGINS', 
                                                'ORDSYS', 'ORDDATA', 'OUTLN', 'ORACLE_OCM', 'OWBSYS', 'OWBSYS_AUDIT',
                                                'PM', 'SCOTT', 'SH', 'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 
                                                'SPATIAL_WFS_ADMIN_USR', 'WMSYS', 'XDB', 'APEX_040200', 'OLAPSYS');
    dummy := simple_html_table('stale-indexes',
                               '<th> owner </th><th> index name </th><th> table owner </th><th> table name </th><th> object type </th><th> last analyzed date </th><th> how to fix </th>',
                               c_stale_indxs);
  exception
    when others then
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>');
      dbms_output.put_line('There is a following error in the printing stale indexes procedure: ' || sqlerrm);
      dbms_output.put_line('</div>');        
  end print_stale_indexes;
  
  /*
  procedure to determine and print out tables having chained or migrated rows.
  when no tables found the sessions stats are to be checked for "table fetch continued row" event which means an access to such kind of rows
  */
  procedure print_chained_rows
  is
    c_chained_rows sys_refcursor;
    row_count number;
    chained_detected varchar2(1) := 'N';
  begin
    open c_chained_rows for select '<tr><td class="left-align">' || owner ||
                                   '</td><td class="left-align">' || table_name ||
                                   '</td><td class="center-align">' || num_rows ||
                                   '</td><td class="center-align">' ||chain_cnt ||
                                   '</td><td class="center-align">' ||chain_cnt/num_rows * 100 || '%' ||
                                   '</td></tr>'
                              from dba_tables t
                             where t.owner not in ('SYS', 'SYSTEM', 'SYSMAN', 'DBSNMP', 'ANONYMOUS', 'APEX_030200', 'APEX_PUBLIC_USER', 
                                                 'APPQOSSYS', 'BI', 'CTXSYS', 'DIP', 'DVSYS', 'EXFSYS', 'FLOWS_FILES',
                                                 'HR', 'IX', 'LBACSYS', 'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OE', 'ORDPLUGINS', 
                                                 'ORDSYS', 'ORDDATA', 'OUTLN', 'ORACLE_OCM', 'OWBSYS', 'OWBSYS_AUDIT',
                                                 'PM', 'SCOTT', 'SH', 'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 
                                                 'SPATIAL_WFS_ADMIN_USR', 'WMSYS', 'XDB', 'APEX_040200', 'OLAPSYS')
                               and t.num_rows > 0
                               and t.chain_cnt/t.num_rows > 0.05 -- chained ratio greater than 5%
                             order by chain_cnt desc;
    row_count := simple_html_table('chained-rows',
                                   '<th>owner</th><th>table name</th><th>rows count (statistics)</th><th>chained rows count (statistics)</th><th>chained rows ratio</th>',
                                   c_chained_rows);                             
                                      
    -- there is another thing to check if there were no chained/migrated rows detected
    if row_count = 0 then
      begin
        select 'Y'
          into chained_detected
          from v$sysstat 
         where name = 'table fetch continued row'
           and value > 0;
      exception
        when others then 
          chained_detected := 'N';
      end;
      -- puts a warning div with a link to oracle doc if "table fetch continued row" has value > 0
      if chained_detected = 'Y' then
        dbms_output.put_line('<div class="news please-note"><span class="icon-span">i</span>');
        dbms_output.put_line('There are no chained rows detected, however the system statistics shows there are sessions events "table fetch continued row" that means accessing such kind of rows.');
        dbms_output.put_line('Please consider to perform the following ');
        dbms_output.put_line('<a target="_blank" and rel="noopener noreferrer" href="https://docs.oracle.com/database/121/SQLRF/statements_4005.htm#SQLRF53683">check</a> (will be opened in another tab)');
        dbms_output.put_line('</div>');
      end if;
    end if;
  exception
    when others then
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>');
      dbms_output.put_line('There is a following error in the printing chained/migrated rows procedure: ' || sqlerrm);
      dbms_output.put_line('</div>');  
  end print_chained_rows;

begin
  -- CSS starts
  l_css := 'div.popup-back{ width: 100%; height: 100%; background-color: rgba(0,0,0,0.5); position: fixed; top: 0; left: 0; z-index: 1;}';
  l_css := l_css || 'div.hidden{ display: none;}';
  l_css := l_css || 'div.visible{ display: block;}';
  l_css := l_css || 'div.popup{ position: fixed; z-index: 1; overflow: auto; /* this enables scroll */ width: 70%; height: 70%; background-color: #fffcee; top: 15%; left: 15%; border-radius: 0.5em; padding: 1em;}';
  l_css := l_css || 'div.popup-show{ display: block;}';
  l_css := l_css || 'table{ margin-left: auto; margin-right: auto; width: 80%; border-collapse: collapse;}';
  l_css := l_css || 'tr{ margin-bottom: 1em;}';
  l_css := l_css || 'tr:nth-of-type(even) { background-color: #DDDDF5;}';  
  l_css := l_css || 'th{ background-color: #055190; text-align: center; padding: 0.5em; vertical-align: middle; color: white;}';
  l_css := l_css || 'td{ text-align: right; padding: 0.5em;}';
  l_css := l_css || '.left-align{ text-align: left;}';
  l_css := l_css || '.right-align{ text-align: right;}';
  l_css := l_css || '.center-align{ text-align: center;}';
  l_css := l_css || 'div#header-div{ text-align: center; background: #055190; width: 80%; margin: auto; }';
  l_css := l_css || 'h1{ display: inline-block; color: white; }';
  l_css := l_css || 'h2, h3{ padding-left: 10%; color: #023057; margin-top: 1.5em;}';
  l_css := l_css || 'h3{ margin-bottom: 1em; font-weight: bold;}';
  l_css := l_css || 'div.news{ padding: 1em; margin: 1em auto 1em auto; width: 80%; border-radius: 0.5em; }';
  l_css := l_css || 'div.good-news{ background-color: #d4edda; }';
  l_css := l_css || 'div.please-note{ background-color: #fff3cd; }';
  l_css := l_css || 'div.bad-news{ background-color: #f8d7da; }';
  l_css := l_css || 'span.icon-span{ font-family: webdings; font-size: 2em; }';
  l_css := l_css || 'div.collect-cmd-btn{ text-align: center; height: 2em; margin-top: 1em; }';
  l_css := l_css || 'button.collect-cmd{ background-color: #DDDDF5; border-radius: 0.5em; height: 100%; font-size: 1em; }';
  l_css := l_css || 'table tbody tr:hover{background-color: #bee5eb;}';
      
  -- CSS ends
  
  -- JS starts
  l_js := 
  'let activePopup = document.createElement("div"); let scrollY; let backDiv = document.getElementById("popup-background");
  activePopup.id = "popup";
  
  //implementation of "closest" for IE
  (function(ELEMENT) {
  ELEMENT.matches = ELEMENT.matches || ELEMENT.mozMatchesSelector || ELEMENT.msMatchesSelector || ELEMENT.oMatchesSelector || ELEMENT.webkitMatchesSelector;
  ELEMENT.closest = ELEMENT.closest || function closest(selector) {
  if (!this) return null;
    if (this.matches(selector)) return this;
    if (!this.parentElement) {return null}
    else return this.parentElement.closest(selector)
    };
  }(Element.prototype));
  
  window.onclick = function(event){
    if (activePopup.innerHTML) { //if activePopup is not empty
      if (event.target.closest("div#popup") != activePopup){
        popupHide();
      }
    }
  }
  function gatherInfo(sqlId, childAddress){
    window.event.cancelBubble = true; // prevents event from bubbling up, the window.onclick will not fire

    // gather active popup content
    activePopup.innerHTML = document.getElementById("sql-" + sqlId + "-" + childAddress).innerHTML + "<hr>";
    let binds = document.getElementById("binds-" + sqlId + "-" + childAddress)
    if(binds){
      activePopup.innerHTML += binds.innerHTML;
    }else{
      activePopup.innerHTML += "<p> No binds captured";
    };

    popupShow();
  }
  function showCommand(pText){
    if(window.event){
      window.event.cancelBubble = true;
    };
    activePopup.innerHTML = "<p>" + pText;
    popupShow();
  }
  function popupShow(){
    activePopup.classList.add("popup");
    activePopup.classList.add("visible");
    
    backDiv.appendChild(activePopup);
    backDiv.classList.remove("hidden");
    backDiv.classList.add("visible");
    
    // save vertical scroll offset
    let nav = navigator.userAgent;
    if (nav.indexOf("MSIE ") > -1 || nav.indexOf("Trident/") > -1){ // if IE
      scrollY = window.pageYOffset;
    }else {
      scrollY = window.scrollY;
    }
    
    document.body.style.overflowY = "hidden"; // prevents body from scrolling when popup is active
  }
  function popupHide(){
    activePopup.innerHTML = ""; //empty popup

    backDiv.removeChild(backDiv.childNodes[0]); // empty backDiv
    backDiv.classList.remove("visible");
    backDiv.classList.add("hidden");

    document.body.style.overflowY = ""; // return scrollbar back
    window.scrollTo(0, scrollY); // return scroll to the position user scrolled before open popup
  }
  // parses the table, assembles all the attributes for each lines'' showCommands and displays it in a popup
    function collectCommands(pTabId, pDivider){
    const CMD_START = "showCommand(''";
    const CMD_END = ";";
    let cmdCollect = "";
    let tabRows = document.getElementById(pTabId).rows;
    // the 0th row is the heading, skip it and start from 1st line
    for(let rowCnt = 1, maxCnt = tabRows.length; rowCnt < maxCnt; rowCnt++){
      let rowCells = tabRows[rowCnt].cells;
      let rawCmd = rowCells[rowCells.length - 1].children[0].onclick.toString(); //get onclick event as a string
      
      cmdCollect += rawCmd.substring(rawCmd.indexOf(CMD_START) + CMD_START.length, rawCmd.lastIndexOf(CMD_END) + CMD_END.length) + "<br>";
	  // divide commands with given divider. Skip if not
	  if(pDivider){
	    cmdCollect += pDivider + "<br>";
	  }
    }
    showCommand(cmdCollect.split("\\").join("")); // a quick way to remove all "\"s from string. it is quick for a developer, not for a browser
  }';
  -- JS ends

  dbms_output.put_line('<!DOCTYPE html><html>');
  print_header(p_title_name => 'DB Report');

  dbms_output.put_line('<body>');  
    dbms_output.put_line('<div id="popup-background" class="popup-back hidden"></div>'); -- div to be shown as popup's background
    
    dbms_output.put_line('<div id="header-div"><h1>Oracle SE performance analysis report</h1></div>');
    
    dbms_output.put_line('<ol>');
    dbms_output.put_line('<h2><li>Objects having stale statistics</li></h2>');
    -- tables having staled statistics
    dbms_output.put_line('<h3>Tables</h3>');
    print_stale_tables();
    print_collect_commands_button('stale-tables');

    -- indexes having stale statistics
    dbms_output.put_line('<h3>Indexes</h3>');
    print_stale_indexes();
    print_collect_commands_button('stale-indexes');
    
    -- fragmented indexes
    dbms_output.put_line('<h2><li>Top ' || g_max_frag_idx_cnt || ' fragmented indexes</li></h2>');
    print_frag_indexes();
    print_collect_commands_button('frag-indexes-stats', '-----------------');
    
    -- fragmented tables
    dbms_output.put_line('<h2><li>Top ' || g_max_frag_tab_cnt || ' fragmented tables</li></h2>');
    print_frag_tables();
    print_collect_commands_button('frag-table-stats', '-----------------');
    
    -- tables having chained/migrated rows
    dbms_output.put_line('<h2><li>Tables having chained/migrated rows</li></h2>');
    print_chained_rows();
        
    -- sql performance stats
    dbms_output.put_line('<h2><li>Resource-intensive queries</li></h2>');
    dbms_output.put_line('<h3>Top ' || g_max_stats_cnt || ' time consuming queries</h3>');
    print_perf_stats_data('time');
    dbms_output.put_line('<h3>Top ' || g_max_stats_cnt || ' disk reads intensive queries</h3>');
    print_perf_stats_data('disk');
    dbms_output.put_line('<h3>Top ' || g_max_stats_cnt || ' logical reads intensive queries</h3>');
    print_perf_stats_data('logical_reads');
    dbms_output.put_line('<h3>Top ' || g_max_stats_cnt || ' cpu consuming queries </h3>');    
    print_perf_stats_data('cpu');
    dbms_output.put_line('</ol>');
    
  dbms_output.put_line(htf.script(l_js)); -- appends JS code
  dbms_output.put_line('</body></html>');
end;
/

quit
