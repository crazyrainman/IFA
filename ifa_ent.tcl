proc getEntity {objEntity expectedEnt checkInverse} {
  global type worksheets nsheet ws_last ws_list opt nproc entName attrtype
  global worksheet cells row col heading ifc colclr lastheading excel count pcount pcountRow lastguid
  global attrsum attrused countEnts ifcApplication invmsg
  global invs last_name rowmax ecount last_row last_p21id env lpnest badattr

# get entity name
  set ifc [$objEntity Type]
  #if {$env(USERDOMAIN) == "NIST"} {if {$ifc != $expectedEnt} {errorMsg "Mismatch: $ifc  $expectedEnt"}}

  incr nproc
  if {[info exists invs]} {unset invs}

  set roseLogical(0) "FALSE"
  set roseLogical(1) "TRUE"
  set roseLogical(2) "UNKNOWN"

# count entities
  set counting 0
  if {$opt(COUNT) && [lsearch $countEnts $ifc] != -1} {set counting 1}

# -------------------------------------------------------------------------------------------------
# open worksheet for each entity if it does not already exist
  if {![info exists worksheet($ifc)]} {
    #set msg "[formatComplexEnt $ifc] ($ecount($ifc))"
    set msg "[formatComplexEnt $ifc] ("
    set rm [expr {$rowmax-3}]
    if {$ecount($ifc) > $rm} {append msg "$rm of "}
    append msg "$ecount($ifc))"
    if {$counting} {append msg "  (Count Duplicates)"}
    outputMsg $msg

    if {$ecount($ifc) > $rm} {errorMsg " Maximum Rows exceeded ($rm)" red}
    if {$ecount($ifc) > 50000 && $rowmax > 50010} {errorMsg " Number of entities > 50000.  Consider using the Maximum Rows option." red}
    update idletasks

    set nsheet [$worksheets Count]
    if {$nsheet < 1} {
      set worksheet($ifc) [$worksheets Item [expr [incr nsheet]]]
    } else {
      set worksheet($ifc) [$worksheets Add [::tcom::na] $ws_last]
    }
    $worksheet($ifc) Activate
    
    lappend ws_list $ifc
    set ws_last $worksheet($ifc)

    set name $ifc
    if {[string length $name] > 31} {
      set name [string range $name 0 30]
      for {set i 1} {$i < 10} {incr i} {
        if {[info exists entName($name)]} {set name "[string range $name 0 29]$i"}
      }
      errorMsg " Worksheet names are truncated to the first 31 characters" red
    }
    set last_name $name
    set ws_name($ifc) [$worksheet($ifc) Name $name]
    set cells($ifc)   [$worksheet($ifc) Cells]
    set heading($ifc) 1
    set last_p21id 0
    set lpnest($ifc,1) 0
    set lpnest($ifc,3) 0

    set row($ifc) 4
    set last_row 4
    $cells($ifc) Item 3 1 "ID"

# set vertical alignment
    $cells($ifc) VerticalAlignment [expr -4160]

    set entName($name) $ifc
    set count($ifc) 0
    set invmsg ""

    foreach var {pcount pcountRow} {if {[info exists $var]} {unset $var}}

    [$worksheet($ifc) Range [cellRange 1 1] [cellRange 1 1]] Select

# color tab
    if {[expr {int([$excel Version])}] >= 12} {
      set cidx [setColorIndex $ifc]
      if {$cidx > 0} {[$worksheet($ifc) Tab] ColorIndex [expr $cidx]}      
    }

    set nsheet [$worksheets Count]
    set ws_last $worksheet($ifc)
    $worksheet($ifc) Activate

# -------------------------------------------------------------------------------------------------
# entity worksheet already open
  } else {
    incr row($ifc)
    set heading($ifc) 0
    set lpnest($ifc,2) 0
  }

# -------------------------------------------------------------------------------------------------
# start filling in the cells

# if less than max allowed rows
  if {$row($ifc) <= $rowmax} {
    set col($ifc) 1
    incr count($ifc)
    
# show progress with > 50000 entities
    if {$ecount($ifc) >= 50000} {
      set c1 [expr {$count($ifc)%20000}]
      if {$c1 == 0} {
        outputMsg " $count($ifc) of $ecount($ifc) processed"
        update idletasks
      }
    }

# entity ID
    set p21id [$objEntity P21ID]

    if {!$counting} {
      $cells($ifc) Item $row($ifc) 1 $p21id

# entity ID when counting (a bit complicated)
    } else {
      if {$row($ifc) > $last_row} {
        $cells($ifc) Item [expr {$row($ifc)-1}] 1 $last_p21id
        if {$count($ifc) == $ecount($ifc)} {$cells($ifc) Item $row($ifc) 1 $p21id}
      } elseif {$ecount($ifc) == 1 || $count($ifc) == $ecount($ifc)} {
        $cells($ifc) Item $row($ifc) 1 $p21id
      }
      set last_row $row($ifc)
      set last_p21id $p21id
    }

# -------------------------------------------------------------------------------------------------
# find inverse relationships for specific entities
    if {$checkInverse} {invFind $objEntity}

    set okinvs 0
    set leninvs 0
    if {[info exists invs]} {
      set leninvs [array size invs]
      if {$leninvs > 0} {set okinvs 1}
    }

# -------------------------------------------------------------------------------------------------
# for all attributes of the entity
    set nattr 0
    set objAttributes [$objEntity Attributes]
    if {$counting} {set lattr [$objAttributes Count]}

    ::tcom::foreach objAttribute $objAttributes {
      set objName [$objAttribute Name]
      #outputMsg "$p21id $objName [$objAttribute NodeType]" red

      if {[catch {
        if {![info exists badattr($ifc)]} {
          set objValue [$objAttribute Value]

# look for bad attributes that cause a crash
        } else {
          set ok 1
          foreach ba $badattr($ifc) {if {$ba == $objName} {set ok 0}}
          if {$ok} {
            set objValue [$objAttribute Value]
          } else {
            set objValue "???"
            errorMsg " Skipping '$objName' attribute on $ifc" red
          }
        }

# error getting attribute value
      } emsgv]} {
        set msg "ERROR processing #[$objEntity P21ID]=[$objEntity Type] '$objName' attribute: $emsgv"
        errorMsg $msg
        set objValue ""
        catch {raise .}
      }

# skip some attributes with IFC files
      set okattr 1
      if {($objName == "OwnerHistory" || $objName == "GlobalId") && !$opt(PR_GUID)} {
        set okattr 0
        if {$counting} {incr lattr -1}
      }

      if {$okattr} {
        incr nattr

# -------------------------------------------------------------------------------------------------
# headings in first row only for first instance of an entity
        if {$heading($ifc) != 0} {
          set ihead 0
          if {[filterHeading $objName] || [string first "IfcAxis" $ifc] == 0} {
            set ihead 1
          }
          if {$ihead} {
            $cells($ifc) Item 3 [incr heading($ifc)] $objName
            set attrtype($heading($ifc)) [$objAttribute Type]
            #outputMsg "  $objName  [$objAttribute Type]"  
            if {[$objAttribute Type] == "STR" || [$objAttribute Type] == "RoseBoolean" || [$objAttribute Type] == "RoseLogical"} {
              set letters ABCDEFGHIJKLMNOPQRSTUVWXYZ
              set c $heading($ifc)
              set inc [expr {int(double($c-1.)/26.)}]
              if {$inc == 0} {
                set c [string index $letters [expr {$c-1}]]
              } else {
                set c [string index $letters [expr {$inc-1}]][string index $letters [expr {$c-$inc*26-1}]]
              }
              set range [$worksheet($ifc) Range "$c:$c"]
              [$range Columns] NumberFormat "@"
            } 

            set inc 0
            if {($objName == "PlacementRelTo" && $objName == $lastheading) || \
                ($objName == "Location" && $lastheading == "RelativePlacement")} {
              set inc 1
            } elseif {$objName == "RelativePlacement" && $lastheading == "RefDirection"} {
              set inc -2
            } elseif {$objName == "RelativePlacement" && $lastheading != "PlacementRelTo"} {
              set inc -1
            }
            if {$inc != 0} {lappend colclr($ifc) "$inc $heading($ifc)"}

            set lastheading $objName
            if {[info exists attrsum]} {
              foreach attr $attrsum {
                if {$objName == $attr} {
                  set count($ifc,$objName) 0
                  if {![info exists attrused]} {
                    set attrused $objName
                  } elseif {[lsearch $attrused $objName] == -1} {
                    lappend attrused $objName
                  }
                }
              }
            }
          }
          if {$ifc == "IfcApplication" && $nattr == 3} {set ifcApplication $objValue}
        }

# -------------------------------------------------------------------------------------------------
# values in rows
        incr col($ifc)

# not a handle, just a single value
        if {[string first "handle" $objValue] == -1} {

# not counting
          if {!$counting} {
            if {[string first "e-308" $objValue] == -1} {
              set ov $objValue

# check for null value?
              if {$ov == -2147483648} {set ov ""}
        
# if value is a boolean, substitute string roseLogical
              if {[$objAttribute Type] == "RoseLogical" || [$objAttribute Type] == "RoseBoolean"} {
                if {$ov == 0 || $ov == 1 || ($ov == 2 && [$objAttribute Type] == "RoseLogical")} {
                  set ov $roseLogical($ov)
                } else {
                  set ov ""
                }
              }
              
# for ListOfdouble (coordinates, directions) add spaces between values
              catch {
                if {$attrtype($col($ifc)) == "ListOfdouble"} {
                  if {[string length $ov] > 0} {
                    regsub -all " " $ov "    " ov
                  } else {
                    errorMsg "Syntax Error: Missing values on: [string toupper $ifc]"
                    #errorMsg "Syntax Error: Missing values on \#$p21id=[string toupper $ifc]"
                  }
                }
              }

# check if displaying numbers without rounding
              catch {
                if {!$opt(XL_FPREC)} {
                  $cells($ifc) Item $row($ifc) $col($ifc) $ov
                } elseif {$attrtype($col($ifc)) != "double" && $attrtype($col($ifc)) != "measure_value"} {
                  $cells($ifc) Item $row($ifc) $col($ifc) $ov
                } elseif {[string length $ov] < 12} {
                  $cells($ifc) Item $row($ifc) $col($ifc) $ov

# no rounding, display as text '
                } else {
                  $cells($ifc) Item $row($ifc) $col($ifc) "'$ov"
                }
              }

              if {[info exists attrsum]} {
                foreach attr $attrsum {
                  if {$objName == $attr && $objValue != ""} {incr count($ifc,$objName)}
                }
              }

# IFC check the GUID if it is being processed
              if {$objName == "GlobalId" && $opt(PR_GUID)} {set lastguid [ifcCheckGUID $objName $ov $lastguid]}
            }

# -------------------------------------------------------------------------------------------------
# count duplicate entities
          } else {
            set ov $objValue

# substitute Real/Integer on IfcPropertySingleValue when counting
            if {$ifc == "IfcPropertySingleValue"} {
              if {$nattr == 3} {
                if {[string is double $ov]} {
                  if {![string is integer $ov]} {
                    set ov "(Real)"
                  } else {
                    set ov "(Integer)"
                  }
                }       
              }
            }

            if {[string first "e-308" $ov] != -1} {set ov ""}
        
# if value is a boolean, substitute string roseLogical
            if {[$objAttribute Type] == "RoseLogical" || [$objAttribute Type] == "RoseBoolean"} {
              if {$ov == 0 || $ov == 1 || ($ov == 2 && [$objAttribute Type] == "RoseLogical")} {
                set ov $roseLogical($ov)
              } else {
                set ov ""
              }
            }
              
# for ListOfdouble (coordinates, directions) add spaces between values
            catch {
              if {$attrtype($col($ifc)) == "ListOfdouble"} {regsub -all " " $ov "    " ov}
            }

# count the entity
            countEntity $ov $objName $nattr $lattr $okinvs
          }

# -------------------------------------------------------------------------------------------------
# if attribute is reference to another entity
        } else {
        
# node type 18=ENTITY, 19=SELECT TYPE  (node type is 20 for SET or LIST is processed below)
          if {[$objAttribute NodeType] == 18 || [$objAttribute NodeType] == 19} {
            set refEntity [$objAttribute Value]

# get refType, however, sometimes this is not a single reference, but rather a list
#  which causes an error and it has to be processed like a list below
            if {[catch {
              set refType [$refEntity Type]
              set valnotlist 1
            } emsg2]} {

# process like a list which is very unusual
              #if {$env(USERDOMAIN) == "NIST"} {errorMsg " Attribute reference is a List: $emsg2"}
              catch {foreach idx [array names cellval] {unset cellval($idx)}}
              ::tcom::foreach val $refEntity {
                append cellval([$val Type]) "[$val P21ID] "
              }
              set str ""
              set size 0
              catch {set size [array size cellval]}

              if {$size > 0} {
                foreach idx [lsort [array names cellval]] {
                  set ncell [expr {[llength [split $cellval($idx) " "]] - 1}]
                  if {$ncell > 1 || $size > 1} {
                    if {$ncell < 30 && !$counting} {
                      append str "($ncell) [formatComplexEnt $idx 1] $cellval($idx)  "
                    } else {
                      append str "($ncell) [formatComplexEnt $idx 1]  "
                    }
                  } else {
                    if {!$counting} {
                      append str "(1) [formatComplexEnt $idx 1] $cellval($idx)  "
                    } else {
                      append str "(1) [formatComplexEnt $idx 1]  "
                    }
                  }
                }
              }
              if {!$counting} {
                $cells($ifc) Item $row($ifc) $col($ifc) [string trim $str]
              } else {
                set ov [string trim $str]
                countEntity $ov $objName $nattr $lattr $okinvs
              }
              set valnotlist 0
            }

# value is not a list which is the most common
            if {$valnotlist} {

# not counting
              if {!$counting} {
                set str "[formatComplexEnt $refType 1] [$refEntity P21ID]"

# for length measure (and other measures), add the actual measure value
                if {$refType == "IfcMeasureWithUnit"} {
                  ::tcom::foreach refAttribute [$refEntity Attributes] {
                    if {[$refAttribute Name] == "ValueComponent"} {set str "[$refAttribute Value]  ($str)"}
                  }
                } elseif {$refType == "IfcMaterial"} {
                  ::tcom::foreach refAttribute [$refEntity Attributes] {
                    if {[$refAttribute Name] == "Name" &&         [$refAttribute Value] != ""} {set str "$str  ([$refAttribute Value])"}
                  }
                } elseif {$refType == "IfcMaterialLayerSet"} {
                  ::tcom::foreach refAttribute [$refEntity Attributes] {
                    if {[$refAttribute Name] == "LayerSetName" && [$refAttribute Value] != ""} {set str "$str  ([$refAttribute Value])"}
                  }
                } elseif {$refType == "IfcMaterialProfileSet"} {
                  ::tcom::foreach refAttribute [$refEntity Attributes] {
                    if {[$refAttribute Name] == "Name" &&         [$refAttribute Value] != ""} {set str "$str  ([$refAttribute Value])"}
                  }
                }

                $cells($ifc) Item $row($ifc) $col($ifc) $str

# counting
              } else {        
                set ov $refType
                countEntity $ov $objName $nattr $lattr $okinvs
              }
            }

# -------------------------------------------------------------------------------------------------
# For IFC, expand IfcLocalPlacement, analysis model entities
            ifcExpandEntities $refType $refEntity $counting

# -------------------------------------------------------------------------------------------------
# node type 20=AGGREGATE (ENTITIES), usually SET or LIST, try as a tcom list or regular list (SELECT type)
          } elseif {[$objAttribute NodeType] == 20} {
            catch {foreach idx [array names cellval]     {unset cellval($idx)}}
            catch {foreach idx [array names cellvalpset] {unset cellvalpset($idx)}}

            if {[catch {
              ::tcom::foreach val [$objAttribute Value] {

# collect the reference id's (P21ID) for the Type of entity in the SET or LIST
                append cellval([$val Type]) "[$val P21ID] "

# -------------------------------------------------------------------------------------------------
# IFC expand IfcPropertySet and IfcElementQuantity
                if {$ifc == "IfcPropertySet" || $ifc == "IfcElementQuantity"} {
                  ::tcom::foreach psetAttribute [$val Attributes] {
                    if {[$psetAttribute Name] == "Name"} {
                      set nam1 [$psetAttribute Value]
                      #append cellvalpset([$val Type]) "\[[$psetAttribute Value]: "
                    }
                    if {[$psetAttribute Name] == "NominalValue" || [$psetAttribute Name] == "Quantities"} {
                      set val1 [$psetAttribute Value]
                      if {$nam1 != $val1 && $val1 != ""} {append cellvalpset([$val Type]) "\[$nam1: $val1\] "}
                    }
                  }
                }
              }

            } emsg]} {
              foreach val [$objAttribute Value] {
                append cellval([$val Type]) "[$val P21ID] "
              }
            }

# -------------------------------------------------------------------------------------------------
# format cell values for the SET or LIST
            set str ""
            set size 0
            catch {set size [array size cellval]}

            if {$size > 0} {
              foreach idx [lsort [array names cellval]] {
                set ncell [expr {[llength [split $cellval($idx) " "]] - 1}]
                if {$ncell > 1 || $size > 1} {
                  if {$ncell < 30 && !$counting} {
                    append str "($ncell) [formatComplexEnt $idx 1] $cellval($idx)  "
                  } else {
                    append str "($ncell) [formatComplexEnt $idx 1]  "
                  }
                } else {
                  if {!$counting} {
                    append str "(1) [formatComplexEnt $idx 1] $cellval($idx)  "
                  } else {
                    append str "(1) [formatComplexEnt $idx 1]  "
                  }
                }
                if {[info exists cellvalpset($idx)]} {
                  if {$ifc == "IfcPropertySet" || $ifc == "IfcElementQuantity"} {append str "$cellvalpset($idx) "}
                }
              }
            }

            if {!$counting} {
              $cells($ifc) Item $row($ifc) $col($ifc) [string trim $str]
            } else {
              set ov [string trim $str]
              countEntity $ov $objName $nattr $lattr $okinvs
            }
          }
        }
      }
    }

# -------------------------------------------------------------------------------------------------
# report inverses    
    if {$leninvs > 0} {invReport $counting}

# rows exceeded
  } else {
    return 0
  }  

# clean up variables to hopefully release some memory
  foreach var {objAttributes invEntity invAttribute subEntity subType objName \
                refEntity refType} {
    if {[info exists $var]} {unset $var}
  }
  update idletasks
  return 1
}
