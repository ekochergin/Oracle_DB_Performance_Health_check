-- 12.1

declare 
  type varchar2_t is table of varchar2(32000); -- being used in print_plsql_table function

  l_css varchar2(32767);
  l_js varchar2(32767);
  
  g_max_frag_idx_cnt constant number := 50; -- max number of fragmented indexes to display
  g_max_frag_tab_cnt constant number := 50; -- max number of fragmented tables to show
  g_max_stats_cnt constant number := 20; -- max number of performance stats to display
  
  /*
  prints head and title tags. all the CSS goes here
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
  prints a clob to the output a clob
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
        dbms_output.put_line('>> l_next_space: ' || l_next_space);
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
  Prints out fragmentation stats for top 50 indexes descending ordered by idx_size / table_size
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
        from dba_users u,
             dba_indexes i,
             dba_tables t,
             dba_segments idx_seg,
             dba_segments tab_seg
       where i.owner = u.username
         and t.owner = i.owner and t.table_name = i.table_name
         and idx_seg.owner = i.owner and idx_seg.segment_name = i.index_name
         and tab_seg.owner = t.owner and tab_seg.segment_name = t.table_name
         and u.oracle_maintained = 'N'
         and t.blocks > 10000
       order by idx_seg.blocks / tab_seg.blocks desc;
  
  begin
    for f_idx in c_frag_idx loop
      exit when l_idx_cnt = g_max_frag_idx_cnt;
      /*
      Chekc only the indexes that weight 20% of table or more
      (this check is somehow quicker here than in the query)
      */
      if f_idx.index_size_pct > 20 then
        execute immediate 'analyze index ' || f_idx.owner || '.' || f_idx.index_name || ' validate structure';
        begin
          select round((del_lf_rows/lf_rows) * 100, 2), height, lf_blks, lf_rows
            into l_ratio, l_height, l_lf_blks, l_lf_rows
            from index_stats
           where lf_rows > 0;
        exception
          when no_data_found then
            l_ratio := null;   
            l_height := null;
            l_lf_rows := null; 
            l_lf_blks := null;
        end;
      end if;
      
      if l_ratio > 20 or l_height >= 4 or l_lf_rows < l_lf_blks then
        l_idx_cnt := l_idx_cnt + 1;
        l_fix_command := 'alter index ' || f_idx.owner || '.' || f_idx.index_name || ' rebuild;';
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
      select round((1 - (dt.avg_row_len * dt.num_rows)/(dt.blocks * p.value)) * 100, 2) frag_rate_pct, 
                            dt.table_name,
                            dt.blocks,
                            dt.owner
                       from dba_users u,
                            dba_tables dt,
                            v$parameter p
                      where dt.owner = u.username
                        and u.ORACLE_MAINTAINED = 'N' -- list all non-oracle users
                        and dt.blocks > 10000 -- filter tiny tables out
                        and dt.num_rows > 0 
                        and dt.avg_row_len > 0
                        and p.name = 'db_block_size'
                        and not exists (select 1 -- since stats data are being used to find fragmented tables there is a need to exclude tables having stale stats
                                          from dba_tab_statistics dts
                                         where dts.stale_stats = 'YES'
                                           and dts.table_name = dt.table_name)
                        and round((1 - (dt.avg_row_len * dt.num_rows)/(dt.blocks * p.value)) * 100, 2) > 20 -- don't let table with small fragm. rate to bother us
                      order by frag_rate_pct desc
                      fetch first g_max_frag_tab_cnt rows with ties;
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
      
      -- assemble fix command (table move + rebuild for all indexes)
      begin
        select listagg('alter index ' || i.owner || '.' || i.index_name || ' rebuild;', '<br>') within group(order by owner) as rebuild_command
          into l_fix_command
          from dba_indexes i 
         where i.table_owner = 'NRGMOERS'
           and i.table_name = 'STOCK_ITEM';
      exception
        when no_data_found then 
          l_fix_command := '';
      end;
      l_fix_command := 'alter table ' || frag_tab.owner || '.' || frag_tab.table_name || ' move;<br>' || l_fix_command;
                                   
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
      select '<tr><td class="left-align">' || s.sql_id ||
             '</td><td class="left-align">' || s.child_address ||
             '</td><td>' || s.END_OF_FETCH_COUNT ||
             '</td><td>' || round(s.elapsed_time / s.END_OF_FETCH_COUNT) * 1000000 ||
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
                  when 'time' then round(s.elapsed_time / s.END_OF_FETCH_COUNT) * 1000000
                  when 'disk' then round(s.disk_reads / s.END_OF_FETCH_COUNT)
                  when 'logical_reads' then round(s.buffer_gets / s.END_OF_FETCH_COUNT)
                  when 'cpu' then round(s.cpu_time / s.END_OF_FETCH_COUNT)
                end desc 
       fetch first g_max_stats_cnt rows only;
    
    queries       clob;  -- stores all the sqls
    l_query_binds varchar2(32767) := ''; -- bind variables' values for a query
    l_all_binds   varchar2(32767); -- all captured values for all variables (I'm sure there is enough space for capturing binds' data)
    -- variables need for debug info
    l_current_sql_id v$sql.sql_id%type;
    l_child_address v$sql.child_address%type;
  begin
    dbms_output.put_line('<table id="sql_perf_' || p_stat_name || '">');
    dbms_output.put_line('<thead><tr><th>sql_id</th><th>child_address</th><th>exec. count</th><th>avg elapsed time, sec</th><th>avg disk reads</th><th>avg logical reads</th><th>avg cpu usage</th><th>module name</th><th>Info</th</tr></thead>');
    for line in stats_data(p_stat_name) loop
      l_current_sql_id := line.sql_id;
      l_child_address := line.child_address;
      dbms_output.put_line(line.val); -- puts out the table row

      -- checks whether there are values for bind variables captured. saves them in a separate div if yes.
      l_query_binds := get_binds(line.sql_id, line.child_address);      
      if length(l_query_binds) > 1 then
        l_all_binds := l_all_binds || '<div id="binds-' || line.sql_id || '-' || line.child_address || '" class="hidden">' /*'" class="bind-values popup">'*/ || l_query_binds || '</div>';
      end if;
      l_query_binds := '';
      
      -- saves query text into a standalone div in a clob where other sqls are being stored
      queries := queries || '<div id="sql-' || line.sql_id || '-' || line.child_address || '" class="hidden">' /*'" class="query-text popup" >'*/ || escape_html_clob(line.sql_fulltext) || '</div>' || chr(10);
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
      dbms_output.put_line('</div');
  end print_perf_stats_data;
  
  procedure print_stale_tables
  is 
    c_stale_tabs sys_refcursor;
    dummy number; 
  begin
    open c_stale_tabs for select '<tr><td class="left-align">'   || owner ||
                                 '</td><td class="left-align">'  || table_name ||
                                 '</td><td class="left-align">'  || object_type ||
                                 '</td><td class="right-align">' || to_char(last_analyzed, 'dd.mm.yyyy hh24:mi:ss') ||
                                 '</td><td><a href=#>Show command</a>' ||
                                 /*'</td><td class="left-align">'  || 'begin dbms_stats.gather_table_stats(''' || owner || ''', ''' || table_name || '''' || 
                                 case when partition_name is not null then ', ''' || partition_name || '''' end || '); end;' || */
                                 '</td></tr>'
                            from dba_tab_statistics 
                           where stale_stats = 'YES';
    dummy := simple_html_table('staleTables', 
                               '<th> owner </th><th> table name </th><th> object type </th><th> last analyzed date </th><th> how to fix </th>', 
                               c_stale_tabs);
  exception
    when others then 
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>');
      dbms_output.put_line('There is a following error in printing stale tables procedure: ' || sqlerrm);
      dbms_output.put_line('</div');
  end print_stale_tables;

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
                            where stale_stats = 'YES';
    dummy := simple_html_table('staleIndexes',
                               '<th> owner </th><th> index name </th><th> table owner </th><th> table name </th><th> object type </th><th> last analyzed date </th><th> how to fix </th>',
                               c_stale_indxs);
  exception
    when others then
      dbms_output.put_line('<div class="news bad-news"><span class="icon-span">r</span>');
      dbms_output.put_line('There is a following error in the printing stale indexes procedure: ' || sqlerrm);
      dbms_output.put_line('</div');        
  end print_stale_indexes;
  
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
                              from dba_tables t,
                                   dba_users u
                             where u.username = t.owner
                               and u.oracle_maintained = 'N' -- show all non-oracle users
                               and t.num_rows > 0
                               and t.chain_cnt/t.num_rows > 0.05 -- chained ratio greater than 5%
                             order by chain_cnt desc;
    row_count := simple_html_table('chainedRows',
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
        dbms_output.put_line('<a target="_blank" and rel="noopener noreferrer" href="https://docs.oracle.com/database/121/SQLRF/statements_4005.htm#SQLRF53683">check</a> (opens in another tab)');
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
  l_css := l_css || 'h3{ margin-bottom: 1em; font-weight: bold; text-align: center;}';
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
  l_css := l_css || 'div.news{ padding: 1em; margin: auto; margin-bottom: 1em; width: 80%; border-radius: 0.5em; }';
  l_css := l_css || 'div.good-news{ background-color: #d4edda; }';
  l_css := l_css || 'div.please-note{ background-color: #fff3cd; }';
  l_css := l_css || 'div.bad-news{ background-color: #f8d7da; }';
  l_css := l_css || 'span.icon-span{ font-family: webdings; font-size: 2em; }';
      
  -- CSS ends
  
  -- JS starts
  l_js := 
  'let activePopup = document.createElement("div"); let scrollY; let backDiv = document.getElementById("popup-background");

  window.onclick = function(event){
    if (activePopup.innerHTML) { //if activePopup is not empty
      if (event.target != activePopup){
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
    window.event.cancelBubble = true;
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

    -- indexes having stale statistics
    dbms_output.put_line('<h3>Indexes</h3>');
    print_stale_indexes();
    
    -- fragmented indexes
    dbms_output.put_line('<h2><li>Top ' || g_max_frag_idx_cnt || ' fragmented indexes</li></h2>');
    print_frag_indexes();
    
    -- fragmented tables
    dbms_output.put_line('<h2><li>Top ' || g_max_frag_tab_cnt || ' fragmented tables</li></h2>');
    print_frag_tables();
    
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
